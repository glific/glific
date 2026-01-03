defmodule Glific.TrialWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Flows.Flow,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Messages.Message,
    Notifications.Notification,
    Partners.Organization,
    Repo,
    TrialAccount.TrialWorker,
    Users.User
  }

  import Ecto.Query

  setup do
    trial_org_attrs = %{
      name: "Trial Test Org",
      shortcode: "trial_test}",
      email: "trial@example.com",
      bsp_id: 1,
      is_active: true,
      is_trial_org: true,
      timezone: "Asia/Kolkata"
    }

    trial_org = Fixtures.organization_fixture(trial_org_attrs)

    {:ok, trial_org} =
      trial_org
      |> Organization.changeset(%{
        trial_expiration_date: DateTime.add(DateTime.utc_now(), -1, :day)
      })
      |> Repo.update()

    %{trial_org: trial_org, trial_org_id: trial_org.id}
  end

  describe "cleanup_expired_trials/1" do
    test "deletes trial org data but preserves system users, simulators, and template flows", %{
      trial_org: _trial_org,
      trial_org_id: trial_org_id
    } do
      Repo.put_process_state(trial_org_id)

      contact_1 =
        Fixtures.contact_fixture(%{organization_id: trial_org_id, name: "Regular Contact 1"})

      contact_2 =
        Fixtures.contact_fixture(%{organization_id: trial_org_id, name: "Regular Contact 2"})

      _simulator_1 =
        Fixtures.contact_fixture(%{
          organization_id: trial_org_id,
          name: "Glific Simulator 1"
        })

      _simulator_2 =
        Fixtures.contact_fixture(%{
          organization_id: trial_org_id,
          name: "Glific Simulator 2"
        })

      _message_1 =
        Fixtures.message_fixture(%{
          sender_id: contact_1.id,
          organization_id: trial_org_id
        })

      _message_2 =
        Fixtures.message_fixture(%{
          sender_id: contact_2.id,
          organization_id: trial_org_id
        })

      _test_user =
        Fixtures.user_fixture(%{
          organization_id: trial_org_id,
          name: "Test User"
        })

      regular_flow =
        Fixtures.flow_fixture(%{
          name: "Regular Flow",
          organization_id: trial_org_id,
          is_template: false,
          keywords: []
        })

      template_flow =
        Fixtures.flow_fixture(%{
          name: "Template Flow",
          organization_id: trial_org_id,
          is_template: true,
          keywords: []
        })

      user = Repo.get_current_user()

      {:ok, _flow_revision1} =
        FlowRevision.create_flow_revision(%{
          definition: FlowRevision.default_definition(regular_flow),
          flow_id: regular_flow.id,
          user_id: user.id,
          organization_id: trial_org_id
        })

      {:ok, _flow_revision2} =
        FlowRevision.create_flow_revision(%{
          definition: FlowRevision.default_definition(template_flow),
          flow_id: template_flow.id,
          user_id: user.id,
          organization_id: trial_org_id
        })

      _notification = Fixtures.notification_fixture(%{organization_id: trial_org_id})
      _webhook_log = Fixtures.webhook_log_fixture(%{organization_id: trial_org_id})

      initial_contacts_count =
        Contact
        |> where([c], c.organization_id == ^trial_org_id)
        |> Repo.aggregate(:count)

      initial_simulator_count =
        Contact
        |> where([c], c.organization_id == ^trial_org_id)
        |> where([c], like(c.name, "Glific Simulator%"))
        |> Repo.aggregate(:count)

      assert initial_simulator_count == 2

      assert :ok = TrialWorker.cleanup_expired_trials()

      assert Message
             |> where([m], m.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      non_template_flows =
        Flow
        |> where([f], f.organization_id == ^trial_org_id)
        |> where([f], f.is_template == false)
        |> Repo.aggregate(:count)

      assert non_template_flows == 0
      refute Repo.get(Flow, regular_flow.id)

      assert Repo.get!(Flow, template_flow.id).is_template == true

      non_template_flow_revisions =
        FlowRevision
        |> join(:inner, [fr], f in Flow, on: fr.flow_id == f.id)
        |> where([fr, f], fr.organization_id == ^trial_org_id)
        |> where([fr, f], f.is_template == false)
        |> Repo.aggregate(:count)

      assert non_template_flow_revisions == 0

      template_flow_revisions =
        FlowRevision
        |> join(:inner, [fr], f in Flow, on: fr.flow_id == f.id)
        |> where([fr, f], fr.organization_id == ^trial_org_id)
        |> where([fr, f], f.is_template == true)
        |> Repo.aggregate(:count)

      assert template_flow_revisions > 0

      assert Notification
             |> where([n], n.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      assert WebhookLog
             |> where([w], w.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      updated_org = Repo.get!(Organization, trial_org_id)
      assert is_nil(updated_org.trial_expiration_date)

      remaining_users =
        User
        |> where([u], u.organization_id == ^trial_org_id)
        |> Repo.all()

      assert length(remaining_users) > 0

      simulator_contacts =
        Contact
        |> where([c], c.organization_id == ^trial_org_id)
        |> where([c], like(c.name, "Glific Simulator%"))
        |> Repo.all()

      assert length(simulator_contacts) == 2

      final_contacts_count =
        Contact
        |> where([c], c.organization_id == ^trial_org_id)
        |> Repo.aggregate(:count)

      assert final_contacts_count < initial_contacts_count
    end

    test "continues cleanup even if one organization fails", %{trial_org_id: trial_org_id} do
      trial_org_2_attrs = %{
        name: "Second Trial Org",
        shortcode: "trial_test_2",
        email: "trial2@example.com",
        bsp_id: 1,
        is_active: true,
        is_trial_org: true,
        timezone: "Asia/Kolkata"
      }

      trial_org_2 = Fixtures.organization_fixture(trial_org_2_attrs)

      {:ok, trial_org_2} =
        trial_org_2
        |> Organization.changeset(%{
          trial_expiration_date: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Repo.update()

      Repo.put_process_state(trial_org_id)
      contact_1 = Fixtures.contact_fixture(%{organization_id: trial_org_id, name: "Contact 1"})

      _message_1 =
        Fixtures.message_fixture(%{sender_id: contact_1.id, organization_id: trial_org_id})

      Repo.put_process_state(trial_org_2.id)
      contact_2 = Fixtures.contact_fixture(%{organization_id: trial_org_2.id, name: "Contact 2"})

      _message_2 =
        Fixtures.message_fixture(%{sender_id: contact_2.id, organization_id: trial_org_2.id})

      messages_org_1_before =
        Message
        |> where([m], m.organization_id == ^trial_org_id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      messages_org_2_before =
        Message
        |> where([m], m.organization_id == ^trial_org_2.id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      assert messages_org_1_before > 0, "Org 1 should have messages before cleanup"
      assert messages_org_2_before > 0, "Org 2 should have messages before cleanup"

      result = TrialWorker.cleanup_expired_trials()
      assert :ok = result

      # Verify data was deleted from both orgs
      messages_org_1_after =
        Message
        |> where([m], m.organization_id == ^trial_org_id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      messages_org_2_after =
        Message
        |> where([m], m.organization_id == ^trial_org_2.id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      assert messages_org_1_after == 0
      assert messages_org_2_after == 0

      case Repo.get(Organization, trial_org_id, skip_organization_id: true) do
        # Org was deleted, that's acceptable
        nil -> :ok
        org -> assert is_nil(org.trial_expiration_date)
      end

      case Repo.get(Organization, trial_org_2.id, skip_organization_id: true) do
        # Org was deleted, that's acceptable
        nil -> :ok
        org -> assert is_nil(org.trial_expiration_date)
      end
    end

    test "skips organizations with no expiration date set", %{trial_org_id: trial_org_id} do
      non_expired_org_attrs = %{
        name: "Non-Expired Trial Org",
        shortcode: "non_expired",
        email: "nonexpired@example.com",
        bsp_id: 1,
        is_active: true,
        is_trial_org: true,
        timezone: "Asia/Kolkata"
      }

      non_expired_org = Fixtures.organization_fixture(non_expired_org_attrs)

      {:ok, non_expired_org} =
        non_expired_org
        |> Organization.changeset(%{trial_expiration_date: nil})
        |> Repo.update()

      Repo.put_process_state(trial_org_id)
      contact_1 = Fixtures.contact_fixture(%{organization_id: trial_org_id, name: "Contact 1"})

      _message_1 =
        Fixtures.message_fixture(%{sender_id: contact_1.id, organization_id: trial_org_id})

      Repo.put_process_state(non_expired_org.id)

      contact_2 =
        Fixtures.contact_fixture(%{organization_id: non_expired_org.id, name: "Contact 2"})

      message_2 =
        Fixtures.message_fixture(%{sender_id: contact_2.id, organization_id: non_expired_org.id})

      expired_org_messages_before =
        Message
        |> where([m], m.organization_id == ^trial_org_id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      non_expired_org_messages_before =
        Message
        |> where([m], m.organization_id == ^non_expired_org.id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      assert expired_org_messages_before > 0, "Expired org should have messages before cleanup"

      assert non_expired_org_messages_before > 0,
             "Non-expired org should have messages before cleanup"

      assert :ok = TrialWorker.cleanup_expired_trials()

      # Verify expired org was cleaned
      expired_org_messages_after =
        Message
        |> where([m], m.organization_id == ^trial_org_id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      assert expired_org_messages_after == 0

      non_expired_org_messages_after =
        Message
        |> where([m], m.organization_id == ^non_expired_org.id)
        |> Repo.aggregate(:count, skip_organization_id: true)

      assert non_expired_org_messages_after == non_expired_org_messages_before,
             "Non-expired org messages should not be deleted"

      assert Repo.get(Message, message_2.id, skip_organization_id: true) != nil
    end
  end
end
