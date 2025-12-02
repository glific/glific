defmodule Glific.Jobs.TrialWorkerTest do
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
    test "deletes all trial org data when trial has expired", %{
      trial_org: _trial_org,
      trial_org_id: trial_org_id
    } do
      Repo.put_process_state(trial_org_id)

      contact_1 = Fixtures.contact_fixture(%{organization_id: trial_org_id})
      contact_2 = Fixtures.contact_fixture(%{organization_id: trial_org_id})

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

      test_user =
        Fixtures.user_fixture(%{
          organization_id: trial_org_id,
          name: "Test User",
          trial_metadata: %{"status" => "active", "organization_name" => "Trial Org"}
        })

      flow = Fixtures.flow_fixture(%{organization_id: trial_org_id})
      user = Repo.get_current_user()

      {:ok, _flow_revision} =
        FlowRevision.create_flow_revision(%{
          definition: FlowRevision.default_definition(flow),
          flow_id: flow.id,
          user_id: user.id,
          organization_id: trial_org_id
        })

      _notification = Fixtures.notification_fixture(%{organization_id: trial_org_id})
      _webhook_log = Fixtures.webhook_log_fixture(%{organization_id: trial_org_id})

      # Verify data exists before cleanup
      assert Message
             |> where([m], m.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) >= 2

      assert Contact
             |> where([c], c.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) >= 2

      assert Flow
             |> where([f], f.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) >= 1

      # Execute cleanup
      assert :ok = TrialWorker.cleanup_expired_trials(trial_org_id)

      assert Message
             |> where([m], m.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      assert Contact
             |> where([c], c.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      assert Flow
             |> where([f], f.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      assert FlowRevision
             |> where([fr], fr.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      assert Notification
             |> where([n], n.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      assert WebhookLog
             |> where([w], w.organization_id == ^trial_org_id)
             |> Repo.aggregate(:count) == 0

      updated_org = Repo.get!(Organization, trial_org_id)
      assert is_nil(updated_org.trial_expiration_date)

      updated_user = Repo.get!(User, test_user.id)
      assert updated_user.trial_metadata["status"] == "expired"
      assert updated_user.trial_metadata["organization_name"] == "Trial Org"
    end
  end
end
