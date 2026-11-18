defmodule Glific.Processor.MessageWorkerTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.Fixtures
  alias Glific.Flows.FlowContext
  alias Glific.Processor.MessageWorker
  alias Glific.Seeds.SeedsDev

  @completion_poll_attempts 100
  @completion_poll_interval_ms 50

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"status" => "submitted", "messageId" => Faker.String.base64(36)})
        }
    end)

    :ok
  end

  test "make_job/1 enqueues the message on the gupshup_inbound queue", %{
    organization_id: organization_id
  } do
    message = Fixtures.message_fixture()

    assert {:ok, %Oban.Job{}} = MessageWorker.make_job(message)

    assert_enqueued(
      worker: MessageWorker,
      queue: :gupshup_inbound,
      args: %{
        message_id: message.id,
        organization_id: organization_id,
        contact_id: message.contact_id
      },
      prefix: "global"
    )
  end

  test "process/1 runs the message through the tagger and flow pipeline" do
    message = Fixtures.message_fixture()

    assert :ok =
             perform_job(MessageWorker, %{
               message_id: message.id,
               organization_id: message.organization_id,
               contact_id: message.contact_id
             })
  end

  test "process/1 still runs a job enqueued without contact_id" do
    message = Fixtures.message_fixture()

    assert :ok =
             perform_job(MessageWorker, %{
               message_id: message.id,
               organization_id: message.organization_id
             })
  end

  describe "per-contact chaining" do
    test "a contact's next message is held until the previous one finishes" do
      contact = Fixtures.contact_fixture()
      other_contact = Fixtures.contact_fixture()

      {:ok, first_job} = enqueue_message(contact, "help")
      {:ok, second_job} = enqueue_message(contact, "help")
      {:ok, other_contact_job} = enqueue_message(other_contact, "help")

      assert first_job.state == "available"
      assert other_contact_job.state == "available"

      assert second_job.state == "scheduled"
      assert second_job.meta["on_hold"] == true
    end

    test "body-less media messages from one contact are chained too" do
      contact = Fixtures.contact_fixture()

      {:ok, first_job} = enqueue_audio_message(contact)
      {:ok, second_job} = enqueue_audio_message(contact)

      assert first_job.state == "available"
      assert second_job.meta["on_hold"] == true
    end

    test "the same keyword sent twice leaves a single active flow run" do
      contact = Fixtures.contact_fixture()

      {:ok, first_job} = enqueue_message(contact, "help")
      {:ok, second_job} = enqueue_message(contact, "help")

      assert %{completed: 2} = drain_inbound_queue()

      assert_single_flow_run(contact)
      assert_ran_in_order(first_job, second_job)
    end

    test "a keyword followed by a prefilled message leaves a single active flow run" do
      contact = Fixtures.contact_fixture()

      {:ok, _first_job} = enqueue_message(contact, "help")
      {:ok, _second_job} = enqueue_message(contact, "Hello! Can I get more info on this?")

      assert %{completed: 2} = drain_inbound_queue()

      assert_single_flow_run(contact)
    end

    test "two messages processed by a live concurrent queue leave a single active flow run" do
      oban_name =
        start_supervised_oban!(
          prefix: "global",
          queues: [gupshup_inbound: 10],
          stage_interval: 10
        )

      contact = Fixtures.contact_fixture()

      jobs =
        ["help", "help"]
        |> Enum.map(&Fixtures.message_fixture(%{body: &1, sender_id: contact.id}))
        |> Enum.map(
          &MessageWorker.new(%{
            message_id: &1.id,
            organization_id: &1.organization_id,
            contact_id: &1.contact_id
          })
        )
        |> Enum.map(&Oban.insert!(oban_name, &1))

      assert_jobs_completed(jobs)
      assert_single_flow_run(contact)
    end

    test "a failed job does not block the contact's next message" do
      contact = Fixtures.contact_fixture()

      {:ok, failing_job} =
        %{message_id: 0, organization_id: contact.organization_id, contact_id: contact.id}
        |> MessageWorker.new()
        |> Oban.insert()

      {:ok, next_job} = enqueue_message(contact, "help")
      assert next_job.meta["on_hold"] == true

      assert %{exhausted: 1, completed: 1} = drain_inbound_queue(with_safety: true)
      assert completed_at(failing_job) == nil
      assert_single_flow_run(contact)
    end
  end

  defp enqueue_message(contact, body) do
    %{body: body, sender_id: contact.id}
    |> Fixtures.message_fixture()
    |> MessageWorker.make_job()
  end

  defp enqueue_audio_message(contact) do
    media = Fixtures.message_media_fixture(%{organization_id: contact.organization_id})

    %{body: nil, type: :audio, media_id: media.id, sender_id: contact.id}
    |> Fixtures.message_fixture()
    |> MessageWorker.make_job()
  end

  defp drain_inbound_queue(opts \\ []) do
    [queue: :gupshup_inbound, with_scheduled: false, prefix: "global"]
    |> Keyword.merge(opts)
    |> drain_jobs()
  end

  defp assert_single_flow_run(contact) do
    active_contexts =
      FlowContext
      |> where([fc], fc.contact_id == ^contact.id)
      |> where([fc], is_nil(fc.completed_at))
      |> Repo.all()

    assert [_single_run] = Enum.filter(active_contexts, &is_nil(&1.parent_id))

    flow_ids = Enum.map(active_contexts, & &1.flow_id)
    assert flow_ids == Enum.uniq(flow_ids)
  end

  defp completed_at(job) do
    Oban.Job
    |> Repo.get!(job.id, prefix: "global")
    |> Map.get(:completed_at)
  end

  defp assert_jobs_completed(jobs, attempts_left \\ @completion_poll_attempts)

  defp assert_jobs_completed(jobs, 0), do: flunk("jobs did not complete: #{inspect(jobs)}")

  defp assert_jobs_completed(jobs, attempts_left) do
    if Enum.all?(jobs, &completed_at/1) do
      :ok
    else
      Process.sleep(@completion_poll_interval_ms)
      assert_jobs_completed(jobs, attempts_left - 1)
    end
  end

  defp assert_ran_in_order(first_job, second_job) do
    first_completed_at = completed_at(first_job)
    second_completed_at = completed_at(second_job)

    assert DateTime.compare(first_completed_at, second_completed_at) == :lt
  end
end
