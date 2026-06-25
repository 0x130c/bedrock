defmodule Bedrock.Compliance.Controls.DuplicateVendor do
  @moduledoc """
  Deterministic Layer-1 Control: two distinct vendor records that share an
  identity key (tax id, bank account) are likely a fraudulent clone or a
  double-entry, and double-paying a cloned vendor is a classic P2P loss.

  Pure and parameterized — given the batch of normalized records, it selects the
  vendors and, for each identity key in `:match_on`, groups them by that key and
  raises one finding per colliding group.

  Options:
    * `:match_on` — identity keys to compare (default `[:tax_id, :bank_account]`)
    * `:exempt_vendors` — vendor ids excluded from collision detection (default `[]`)
  """
  @behaviour Bedrock.Compliance.Control

  @control_name "Duplicate Vendor"
  @default_match_on [:tax_id, :bank_account]

  @impl true
  def control_name, do: @control_name

  @impl true
  def findings(records, opts) do
    match_on = Keyword.get(opts, :match_on, @default_match_on)
    exempt = MapSet.new(Keyword.get(opts, :exempt_vendors, []))

    vendors =
      records
      |> Enum.filter(&vendor?/1)
      |> Enum.reject(fn vendor -> MapSet.member?(exempt, Map.get(vendor, :id)) end)

    match_on
    |> Enum.flat_map(fn key -> collisions(vendors, key) end)
    |> Enum.uniq_by(fn finding -> vendor_ids(finding.evidence.vendors) end)
  end

  defp collisions(vendors, key) do
    vendors
    |> Enum.group_by(&Map.get(&1, key))
    |> Enum.filter(fn {value, group} -> not is_nil(value) and length(group) > 1 end)
    |> Enum.map(fn {value, group} -> finding(key, value, group) end)
  end

  defp vendor?(record), do: Map.get(record, :type) == :vendor
  defp vendor_ids(vendors), do: vendors |> Enum.map(&Map.get(&1, :id)) |> Enum.sort()

  defp finding(key, value, vendors) do
    ids = vendors |> Enum.map(&Map.get(&1, :id)) |> Enum.join(", ")

    %{
      subject: "Vendors #{ids}",
      # The colliding vendor set is the canonical fingerprint — re-ingesting the same
      # clone reopens no second Case (ADR-0011), independent of which key matched.
      finding_key: vendor_ids(vendors) |> Enum.join(","),
      evidence: %{matched_on: key, value: value, vendors: vendors},
      reason:
        "Control '#{@control_name}' breached: vendors #{ids} share the same " <>
          "#{key} #{value}."
    }
  end
end
