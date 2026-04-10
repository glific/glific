defmodule Glific.ChatbotDiagnoseTest do
  use Glific.DataCase, async: true

  alias Glific.{
    ChatbotDiagnose,
    Contacts,
    Fixtures,
    Flows,
    Repo
  }

  describe "diagnose/2" do
    test "returns org-level overview when no contact or flow filter" do
      org_id = Fixtures.get_org_id()

      {:ok, result} = ChatbotDiagnose.diagnose(org_id, %{})

      assert is_list(result.notifications)
      assert is_list(result.oban_jobs)
      assert is_map(result.diagnostics)
      assert is_integer(result.diagnostics.recent_error_count)
      assert is_integer(result.diagnostics.pending_oban_jobs)
      assert is_nil(result.contact_info)
      assert is_nil(result.flow_info)
    end

    test "returns contact data when contact filter provided" do
      org_id = Fixtures.get_org_id()
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          contact: %{phone: contact.phone}
        })

      assert result.contact_info != nil
      assert result.contact_info.phone == contact.phone
      assert is_list(result.messages)
      assert is_list(result.contact_history)
      assert is_map(result.diagnostics)
    end

    test "returns flow data when flow filter provided" do
      org_id = Fixtures.get_org_id()

      [flow | _] =
        Flows.list_flows(%{filter: %{organization_id: org_id}, opts: %{limit: 1}})

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          flow: %{name: flow.name}
        })

      assert result.flow_info != nil
      assert result.flow_info.name == flow.name
      assert is_list(result.flow_revisions)
      assert is_list(result.triggers)
    end

    test "respects include filter to limit sections" do
      org_id = Fixtures.get_org_id()
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          contact: %{phone: contact.phone},
          include: ["CONTACT_INFO", "MESSAGES"]
        })

      assert result.contact_info != nil
      # Sections not in include should be empty defaults
      assert result.flow_info == nil
      assert result.triggers == []
    end

    test "respects time_range parameter" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          time_range: "1h"
        })

      assert is_list(result.notifications)
      assert is_map(result.diagnostics)
    end

    test "respects limit parameter" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          limit: 5
        })

      assert length(result.notifications) <= 5
      assert length(result.oban_jobs) <= 5
    end

    test "diagnostics computed fields are correct types" do
      org_id = Fixtures.get_org_id()
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          contact: %{phone: contact.phone}
        })

      diag = result.diagnostics
      assert diag.contact_opted_in in [true, false]
      assert is_integer(diag.recent_error_count)
      assert is_integer(diag.pending_oban_jobs)
    end

    test "returns nil for contact_info when contact not found" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        ChatbotDiagnose.diagnose(org_id, %{
          contact: %{phone: "000000000000"}
        })

      assert result.contact_info == nil
    end
  end
end
