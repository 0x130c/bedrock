defmodule Bedrock.ComplianceTest do
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance
  alias Bedrock.Compliance.Connection

  setup do
    org =
      Compliance.create_organization!(%{name: "Acme #{System.unique_integer([:positive])}"})

    connection =
      Compliance.create_connection!(
        %{name: "Primary", odoo_url: "https://acme.odoo.com", credential: "ro-secret"},
        tenant: org
      )

    %{org: org, connection: connection}
  end

  defp breaching_po do
    %{
      id: "PO0042",
      amount_total: 750_000_000,
      currency: "VND",
      approvals: [%{role: "manager"}]
    }
  end

  describe "ingest_events/3" do
    test "a PO above threshold without the required approval opens a Case bundling a Violation and HardEvidence",
         %{org: org, connection: connection} do
      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, [breaching_po()], tenant: org)

      case_record = Ash.load!(case_record, [:violation, :hard_evidence], tenant: org)

      assert case_record.violation.control_name == "Threshold Approval"
      assert case_record.violation.reason =~ "PO0042"
      assert case_record.violation.reason =~ "CFO"
      assert case_record.hard_evidence.snapshot["id"] == "PO0042"
      assert case_record.hard_evidence.snapshot["amount_total"] == 750_000_000
    end

    test "a batch of only compliant POs opens no Cases", %{org: org, connection: connection} do
      compliant = [
        %{id: "PO0100", amount_total: 100_000_000, currency: "VND", approvals: []},
        %{
          id: "PO0101",
          amount_total: 900_000_000,
          currency: "VND",
          approvals: [%{role: "CFO"}]
        }
      ]

      assert {:ok, []} = Compliance.ingest_events(connection, compliant, tenant: org)
      assert [] = Compliance.list_cases!(tenant: org)
    end

    test "Cases opened under one Organization are invisible to another (schema isolation)",
         %{org: org_a, connection: conn_a} do
      org_b =
        Compliance.create_organization!(%{name: "Beta #{System.unique_integer([:positive])}"})

      assert {:ok, [_case]} = Compliance.ingest_events(conn_a, [breaching_po()], tenant: org_a)

      assert [_one] = Compliance.list_cases!(tenant: org_a)
      assert [] = Compliance.list_cases!(tenant: org_b)
    end
  end

  describe "connection credentials" do
    test "the read-only Odoo credential is encrypted at rest and decrypts through the resource",
         %{org: org, connection: connection} do
      reloaded = Ash.get!(Connection, connection.id, tenant: org)

      # The persisted column holds ciphertext, never the plaintext credential.
      assert is_binary(reloaded.encrypted_credential)
      refute reloaded.encrypted_credential == "ro-secret"

      # Loading the decrypting calculation returns the original plaintext.
      decrypted = Ash.load!(reloaded, :credential, tenant: org)
      assert decrypted.credential == "ro-secret"
    end
  end
end
