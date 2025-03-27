defmodule Glific.Processor.ConsumerFlowTest do
  use ExUnit.Case, async: false
  alias Glific.Flows.FlowContext
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Flows.Flow,
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
    8 => "👍",
    9 => "2",
    10 => "We are Glific",
    11 => "4"
  }
  @checks_size Enum.count(@checks)

  test "should start the flow" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    Enum.map(
      0..(@checks_size - 1),
      fn c ->
        message =
          Fixtures.message_fixture(%{body: @checks[rem(c, @checks_size)], sender_id: sender.id})
          |> Repo.preload([:contact])

        ConsumerFlow.process_message({message, state}, message.body)
      end
    )

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + @checks_size
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
    assert new_message_count > message_count + 1
  end

  test "test template flows" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    message =
      Fixtures.message_fixture(%{body: "template:Direct with GPT", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, "templatedirectwithgpt")

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + 1
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
    assert new_message_count > message_count + Enum.count(@checks_1)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})
    assert sender.optin_status == false
    assert !is_nil(sender.optout_time)
  end

  test "check regx flow sequence" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    # The default regex config matches the word `unique_regex`
    message =
      Fixtures.message_fixture(%{body: "unique_regex", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, message.body)

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + 1
  end

  test "should not start optin flow when flow is inactive" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    sender =
      Repo.get_by(Contact, %{name: "Chrissy Cron"})
      |> Contact.changeset(%{
        status: :invalid,
        optin_time: nil,
        optout_time: ~U[2023-12-22 12:00:00Z],
        optin_method: nil,
        optin_status: false,
        is_contact_replied: false
      })

    sender = Repo.update!(sender)

    flow =
      Repo.get_by(Flow, name: "Optin Workflow")
      |> Flow.changeset(%{is_active: false})
      |> Repo.update!()

    message =
      Fixtures.message_fixture(%{body: "hey", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, message.body)

    latest_message =
      Repo.one(
        from m in Message,
          where: m.sender_id == ^sender.id,
          order_by: [desc: m.inserted_at],
          limit: 1
      )

    assert latest_message.body == "hey"

    flow_context =
      Repo.get_by(FlowContext, contact_id: sender.id, flow_id: flow.id)

    assert flow_context == nil
  end
end
