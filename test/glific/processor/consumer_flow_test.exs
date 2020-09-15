defmodule Glific.Processor.ConsumerFlowTest do
  use Glific.DataCase

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Messages.Message,
    Processor.ConsumerFlow,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  @checks %{
    0 => "help",
    1 => "does not exist",
    2 => "still does not exist",
    3 => "2",
    4 => "language",
    5 => "no language",
    6 => "2",
    7 => "newcontact",
    8 => "2",
    9 => "We are Glific",
    10 => "4"
  }
  @checks_size Enum.count(@checks)

  test "should start the flow" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    Enum.map(
      0..@checks_size,
      fn c ->
        message =
          Fixtures.message_fixture(%{body: @checks[rem(c, @checks_size)], sender_id: sender.id})
          |> Repo.preload([:contact])

        ConsumerFlow.process_message({message, state}, message.body)
      end
    )

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count
  end
end
