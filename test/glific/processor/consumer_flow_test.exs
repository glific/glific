defmodule Glific.Processor.ConsumerFlowTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
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
    SeedsDev.seed_interactives()

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "name" => "Opted In Contact",
              "phone" => "A phone number"
            })
        }
    end)

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

  test "test draft flows" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    message =
      Fixtures.message_fixture(%{body: "draft:help", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, "drafthelp")

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count
  end

  @checks_1 [
    "optin",
    "👍",
    "optout",
    "1"
  ]

  defp send_messages(list, sender, receiver) do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    Enum.map(
      list,
      fn c ->
        message =
          Fixtures.message_fixture(%{
            body: c,
            sender_id: sender.id,
            receiver_id: receiver.id
          })
          |> Map.put(:contact_id, sender.id)
          |> Map.put(:contact, sender)

        ConsumerFlow.process_message({message, state}, message.body)
      end
    )
  end

  test "check optin/optout sequence" do
    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    {:ok, sender} =
      Repo.get_by(Contact, %{name: "Chrissy Cron"})
      |> Contacts.update_contact(%{phone: "919917443332"})

    receiver = Repo.get_by(Contact, %{name: "NGO Main Account"})

    send_messages(@checks_1, sender, receiver)

    # We should add check that there is a set of optin and optout message here
    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})
    assert sender.optin_status == false
    assert !is_nil(sender.optout_time)
  end
end
