defmodule Bedrock.Compliance.Controls.ThreeWayMatch do
  @moduledoc """
  Deterministic Layer-1 Control: the 3-way match. A Vendor Bill should agree with
  what was ordered (Purchase Order) and what arrived (Goods Receipt). Being billed
  for more than was received, or at a higher unit price than the PO, surfaces
  before payment.

  Pure and parameterized — given the batch of normalized records, it links the PO,
  Goods Receipt(s) and Vendor Bill(s) sharing a PO reference and raises one finding
  per linked set whose quantity or price disagrees beyond tolerance.

  Only documents *present in the batch* are compared: with no Goods Receipt the
  quantity arm is skipped and with no PO the price arm is skipped, so a triad split
  across ingestion batches is never a false positive (a missing receipt is a
  Conformance Deviation's concern, not this Control's).

  Options:
    * `:quantity_tolerance` — allowed |billed − received| before a quantity breach (default `0`)
    * `:price_tolerance` — allowed |bill price − PO price| before a price breach (default `0`)
  """
  @behaviour Bedrock.Compliance.Control

  @control_name "Three-Way Match"

  @impl true
  def control_name, do: @control_name

  @impl true
  def findings(records, opts) do
    quantity_tolerance = Keyword.get(opts, :quantity_tolerance, 0)
    price_tolerance = Keyword.get(opts, :price_tolerance, 0)

    pos = records |> Enum.filter(&type?(&1, :purchase_order)) |> Map.new(&{Map.get(&1, :id), &1})

    grs =
      records |> Enum.filter(&type?(&1, :goods_receipt)) |> Enum.group_by(&Map.get(&1, :po_ref))

    bills =
      records |> Enum.filter(&type?(&1, :vendor_bill)) |> Enum.group_by(&Map.get(&1, :po_ref))

    bills
    |> Enum.reject(fn {po_ref, _} -> is_nil(po_ref) end)
    |> Enum.flat_map(fn {po_ref, vendor_bills} ->
      triad = %{
        po_ref: po_ref,
        po: Map.get(pos, po_ref),
        goods_receipts: Map.get(grs, po_ref, []),
        vendor_bills: vendor_bills
      }

      case mismatches(triad, quantity_tolerance, price_tolerance) do
        [] -> []
        mismatches -> [finding(triad, mismatches)]
      end
    end)
  end

  defp type?(record, type), do: Map.get(record, :type) == type

  defp mismatches(triad, quantity_tolerance, price_tolerance) do
    quantity_mismatch(triad, quantity_tolerance) ++ price_mismatch(triad, price_tolerance)
  end

  defp quantity_mismatch(%{goods_receipts: []}, _tolerance), do: []

  defp quantity_mismatch(triad, tolerance) do
    received = sum_quantity(triad.goods_receipts)
    billed = sum_quantity(triad.vendor_bills)
    gap = Decimal.abs(Decimal.sub(billed, received))

    if Decimal.compare(gap, Decimal.new(tolerance)) == :gt, do: [:quantity], else: []
  end

  defp price_mismatch(%{po: nil}, _tolerance), do: []

  defp price_mismatch(triad, tolerance) do
    po_price = Map.get(triad.po, :unit_price)

    breached? =
      Enum.any?(triad.vendor_bills, fn bill ->
        price_breached?(Map.get(bill, :unit_price), po_price, tolerance)
      end)

    if breached?, do: [:price], else: []
  end

  # Per-currency (ADR-0011): unit prices are `Money`; the gap is compared against the
  # tolerance read in the same currency. A missing price defaults to zero of the
  # other's currency so a one-sided price still surfaces.
  defp price_breached?(nil, nil, _tolerance), do: false

  defp price_breached?(bill_price, po_price, tolerance) do
    bill_price = bill_price || zero_like(po_price)
    po_price = po_price || zero_like(bill_price)
    gap = Money.abs(Money.sub!(bill_price, po_price))

    Money.compare(gap, Money.new(bill_price.currency, tolerance)) == :gt
  end

  defp zero_like(%Money{currency: currency}), do: Money.new(currency, 0)

  defp sum_quantity(records) do
    records
    |> Enum.map(&(Map.get(&1, :quantity) || Decimal.new(0)))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp finding(triad, mismatches) do
    %{
      subject: "PO #{triad.po_ref}",
      # The breach is Episode-grained per Purchase Order: re-ingesting the same
      # triad must reopen no second Case, so the PO reference is the finding_key.
      finding_key: to_string(triad.po_ref),
      evidence: Map.put(triad, :mismatches, mismatches),
      reason:
        "Control '#{@control_name}' breached: PO #{triad.po_ref} fails the 3-way match on " <>
          "#{Enum.join(mismatches, " and ")} " <>
          "(received #{sum_quantity(triad.goods_receipts)}, billed #{sum_quantity(triad.vendor_bills)})."
    }
  end
end
