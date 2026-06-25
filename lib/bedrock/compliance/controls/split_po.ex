defmodule Bedrock.Compliance.Controls.SplitPo do
  @moduledoc """
  Deterministic Layer-1 Control: an approval threshold is dodged by splitting one
  large purchase into several sub-threshold Purchase Orders to the same vendor in
  a short window. Each PO passes the threshold check alone; together they breach it.

  Pure and parameterized — given the batch of normalized records, it selects the
  POs, groups them by vendor, partitions each vendor's orders into windows of
  `:window_hours`, and raises one finding per window whose orders combine above
  `:threshold`.

  Options:
    * `:threshold` — the combined amount above which a cluster is a breach (required)
    * `:window_hours` — the span within which orders are considered one attempt (required)
    * `:exempt_vendors` — vendor ids excluded from detection (default `[]`)
  """
  @behaviour Bedrock.Compliance.Control

  @control_name "Split PO"

  @impl true
  def control_name, do: @control_name

  # Cross-batch correlation (ADR-0011): split-PO evasion is *temporal* — sub-threshold
  # orders issued to one vendor over days. The seam replays each touched vendor's
  # recent POs so halves landing in separate polls are clustered. The lookback equals
  # the clustering window: an order farther back than that can never join a window
  # anchored on a batch order.
  @window_hours 72

  @impl true
  def correlation,
    do: %{
      types: [:purchase_order],
      key: &Map.get(&1, :vendor_id),
      lookback: {@window_hours, :hour}
    }

  @impl true
  def findings(records, opts) do
    threshold = Keyword.fetch!(opts, :threshold)
    window_hours = Keyword.fetch!(opts, :window_hours)
    exempt = MapSet.new(Keyword.get(opts, :exempt_vendors, []))

    records
    |> Enum.filter(&po?/1)
    |> Enum.filter(&Map.get(&1, :amount_total))
    |> Enum.reject(fn po -> MapSet.member?(exempt, Map.get(po, :vendor_id)) end)
    # Per-currency (ADR-0011): cluster within a single currency, so a window's
    # combined total is never summed across currencies.
    |> Enum.group_by(fn po -> {Map.get(po, :vendor_id), currency(po)} end)
    |> Enum.flat_map(fn {{vendor_id, _currency}, orders} ->
      orders
      |> windows(window_hours)
      |> Enum.filter(fn cluster ->
        length(cluster) > 1 and over_threshold?(cluster, threshold)
      end)
      |> Enum.map(fn cluster -> finding(vendor_id, cluster, threshold) end)
    end)
  end

  defp po?(record), do: Map.get(record, :type) == :purchase_order
  defp currency(po), do: Map.get(po, :amount_total).currency

  defp over_threshold?(cluster, threshold) do
    Money.compare(combined(cluster), threshold_money(cluster, threshold)) == :gt
  end

  defp threshold_money(cluster, threshold), do: Money.new(currency(hd(cluster)), threshold)

  # Greedily partition a vendor's orders, sorted by date, into disjoint windows:
  # each window holds every order within `window_hours` of the window's first order.
  defp windows(orders, window_hours) do
    window_seconds = window_hours * 3600

    orders
    |> Enum.sort_by(&Map.get(&1, :order_date), DateTime)
    |> Enum.reduce([], fn po, clusters ->
      case clusters do
        # `current` is built newest-first (prepend), so the window's *first* order — the
        # fixed anchor every member is measured against — is its last element. Anchoring
        # on the most-recent order instead would slide the window forward indefinitely,
        # chaining ≤window-spaced orders into one cluster that spans far more than a window.
        [current | rest] ->
          if within?(po, List.last(current), window_seconds) do
            [[po | current] | rest]
          else
            [[po], current | rest]
          end

        [] ->
          [[po]]
      end
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end

  defp within?(po, anchor, window_seconds) do
    DateTime.diff(Map.get(po, :order_date), Map.get(anchor, :order_date)) <= window_seconds
  end

  defp combined(orders) do
    orders |> Enum.map(&Map.get(&1, :amount_total)) |> Enum.reduce(&Money.add!(&2, &1))
  end

  # The window's anchor — its earliest order — buckets the cluster deterministically.
  defp window_anchor(orders),
    do: orders |> Enum.map(&Map.get(&1, :order_date)) |> Enum.min(DateTime)

  defp finding(vendor_id, orders, threshold) do
    ids = orders |> Enum.map(&Map.get(&1, :id)) |> Enum.join(", ")
    total = combined(orders)

    %{
      subject: "Vendor #{vendor_id}",
      # Episode-grained per vendor + window: the cluster's anchor (its earliest
      # order) buckets the window, so the same split attempt re-ingested reopens no
      # second Case (ADR-0011).
      finding_key: "#{vendor_id}|#{DateTime.to_unix(window_anchor(orders))}",
      evidence: %{vendor_id: vendor_id, orders: orders, combined_total: total},
      reason:
        "Control '#{@control_name}' breached: orders #{ids} to vendor #{vendor_id} " <>
          "combine to #{Money.to_string!(total)}, above the " <>
          "#{Money.to_string!(threshold_money(orders, threshold))} threshold, while each " <>
          "stays under it."
    }
  end
end
