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

    if abs(billed - received) > tolerance, do: [:quantity], else: []
  end

  defp price_mismatch(%{po: nil}, _tolerance), do: []

  defp price_mismatch(triad, tolerance) do
    po_price = Map.get(triad.po, :unit_price) || 0

    breached? =
      Enum.any?(triad.vendor_bills, fn bill ->
        abs((Map.get(bill, :unit_price) || 0) - po_price) > tolerance
      end)

    if breached?, do: [:price], else: []
  end

  defp sum_quantity(records) do
    records |> Enum.map(&(Map.get(&1, :quantity) || 0)) |> Enum.sum()
  end

  defp finding(triad, mismatches) do
    %{
      subject: "PO #{triad.po_ref}",
      evidence: Map.put(triad, :mismatches, mismatches),
      reason:
        "Control '#{@control_name}' breached: PO #{triad.po_ref} fails the 3-way match on " <>
          "#{Enum.join(mismatches, " and ")} " <>
          "(received #{sum_quantity(triad.goods_receipts)}, billed #{sum_quantity(triad.vendor_bills)})."
    }
  end
end
