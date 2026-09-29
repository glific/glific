defmodule Glific.Processor.MessageWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Processor.MessageWorker,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
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
      args: %{message_id: message.id, organization_id: organization_id},
      prefix: "global"
    )
  end

  test "perform/1 runs the message through the tagger and flow pipeline" do
    message = Fixtures.message_fixture()

    assert :ok =
             perform_job(MessageWorker, %{
               message_id: message.id,
               organization_id: message.organization_id
             })
  end
end
