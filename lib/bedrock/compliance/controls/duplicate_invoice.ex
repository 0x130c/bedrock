defmodule Bedrock.Compliance.Controls.DuplicateInvoice do
  @moduledoc """
  Deterministic Layer-1 Control: the same vendor bill entered twice is a classic
  double-payment risk. Two bills are duplicates when they agree on every identity
  key — by default the same vendor and the same invoice number.

  Pure and parameterized — given the batch of normalized records, it selects the
  vendor bills, groups them by their composite identity key, and raises one
  finding per colliding group.

  Options:
    * `:match_on` — fields forming the duplicate key (default `[:vendor_id, :invoice_number]`)
    * `:exempt_vendors` — vendor ids excluded from detection (default `[]`)
  """
  @behaviour Bedrock.Compliance.Control

  @control_name "Duplicate Invoice"
  @default_match_on [:vendor_id, :invoice_number]

  @impl true
  def control_name, do: @control_name

  @impl true
  def findings(records, opts) do
    match_on = Keyword.get(opts, :match_on, @default_match_on)
    exempt = MapSet.new(Keyword.get(opts, :exempt_vendors, []))

    records
    |> Enum.filter(&bill?/1)
    |> Enum.reject(fn bill -> MapSet.member?(exempt, Map.get(bill, :vendor_id)) end)
    |> Enum.group_by(fn bill -> key(bill, match_on) end)
    |> Enum.filter(fn {key, group} -> complete_key?(key) and length(group) > 1 end)
    |> Enum.map(fn {_key, group} -> finding(group, match_on) end)
  end

  defp bill?(record), do: Map.get(record, :type) == :vendor_bill

  defp key(bill, match_on), do: Enum.map(match_on, &Map.get(bill, &1))
  defp complete_key?(key), do: Enum.all?(key, &(not is_nil(&1)))

  defp finding(bills, match_on) do
    ids = bills |> Enum.map(&Map.get(&1, :id)) |> Enum.join(", ")
    [sample | _] = bills
    invoice_number = Map.get(sample, :invoice_number)
    vendor_id = Map.get(sample, :vendor_id)

    %{
      subject: "Invoice #{invoice_number}",
      evidence: %{matched_on: match_on, bills: bills},
      reason:
        "Control '#{@control_name}' breached: vendor bills #{ids} from vendor " <>
          "#{vendor_id} share invoice number #{invoice_number}."
    }
  end
end
