defmodule TestConsumerTagger do
  use GenStage

  alias Glific.{
    Fixtures,
    Processor.ConsumerAutomation,
    Repo,
    Settings.Language,
    Tags,
    Tags.Tag
  }

  def start_link(demand) do
    GenStage.start_link(__MODULE__, demand, name: TestConsumerTagger)
  end

  def init(demand) do
    tag_ids = Tags.tags_map(["New Contact", "Language", "Optout", "Help"])
    language_ids = Repo.label_id_map(Language, ["Hindi", "English (United States)"])

    state = %{
      counter: demand,
      new_contact_tag_id: tag_ids["New Contact"],
      language_tag_id: tag_ids["Language"],
      optout_tag_id: tag_ids["Optout"],
      help_tag_id: tag_ids["Help"],
      language_id: language_ids["Hindi"]
    }

    {:producer, state, dispatcher: GenStage.BroadcastDispatcher}
  end

  defp create_message_tag(tag_id, language_id, body, value \\ nil) do
    m = Fixtures.message_fixture(%{body: body, language_id: language_id})
    {:ok, _} = Tags.create_message_tag(%{message_id: m.id, tag_id: tag_id, value: value})
    m = Repo.preload(m, :tags)
    [ht | _] = m.tags
    [m, ht]
  end

  defp create_message_new_contact(%{
         new_contact_tag_id: new_contact_tag_id,
         language_id: language_id
       }) do
    create_message_tag(
      new_contact_tag_id,
      language_id,
      "Test message for testing new contact tag"
    )
  end

  defp create_message_language(
         %{language_tag_id: language_tag_id, language_id: language_id},
         value
       ) do
    create_message_tag(
      language_tag_id,
      language_id,
      "Test message for testing language switch",
      value
    )
  end

  defp create_message_optout(%{optout_tag_id: optout_tag_id, language_id: language_id}) do
    create_message_tag(optout_tag_id, language_id, "Test message for testing optout tag")
  end

  defp create_message_help(%{help_tag_id: help_tag_id, language_id: language_id}) do
    create_message_tag(help_tag_id, language_id, "Test message for testing help tag")
  end

  def handle_demand(demand, %{counter: counter} = state) when counter < 6 do
    events =
      Enum.map(
        counter..(counter + demand - 1),
        fn _ ->
          [
            Fixtures.message_fixture(%{
              body: "This is just a filler message while we wait",
              language_id: state.language_id
            }),
            %Tag{}
          ]
        end
      )

    {:noreply, events, Map.put(state, :counter, demand + counter)}
  end

  def handle_demand(_demand, %{counter: counter} = state) when counter > 12 do
    send(:test, {:called_back})
    {:stop, :normal, state}
  end

  def handle_demand(demand, %{counter: counter} = state) when demand > 0 do
    events =
      Enum.map(
        counter..(counter + demand - 1),
        fn c ->
          case rem(c, 7) do
            0 -> create_message_optout(state)
            1 -> create_message_new_contact(state)
            2 -> create_message_language(state, "english")
            3 -> create_message_new_contact(state)
            4 -> create_message_language(state, "हिंदी")
            5 -> create_message_language(state, "hindi")
            6 -> create_message_help(state)
          end
        end
      )

    {:noreply, events, Map.put(state, :counter, demand + counter)}
  end
end

defmodule Glific.Processor.ConsumerAutomationTest do
  use Glific.DataCase

  alias Glific.{
    Messages,
    Messages.Message,
    Processor.ConsumerAutomation,
    Processor.ConsumerHelp,
    Processor.ConsumerLanguage,
    Processor.ConsumerNewContact,
    Processor.ConsumerOptout,
    Repo
  }

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    Glific.Seeds.seed_session_templates(lang)
    :ok
  end

  test "should behave like consumer" do
    original_count = Repo.aggregate(Message, :count)

    {:ok, producer} = TestConsumerTagger.start_link(1)

    {:ok, _consumer} =
      ConsumerAutomation.start_link(producer: producer, name: TestConsumerAutomation)

    {:ok, _consumer} = ConsumerLanguage.start_link(producer: producer, name: TestConsumerLanguage)

    {:ok, _consumer} =
      ConsumerNewContact.start_link(producer: producer, name: TestConsumerNewContact)

    {:ok, _consumer} = ConsumerOptout.start_link(producer: producer, name: TestConsumerOptout)

    {:ok, _consumer} = ConsumerHelp.start_link(producer: producer, name: TestConsumerHelp)

    Process.register(self(), :test)
    assert_receive({:called_back}, 1000)

    # ensure we have a few more messages in the DB
    assert Repo.aggregate(Message, :count) > original_count

    # IO.inspect(Repo.query("select id, body from messages"))
    # Lets add checks here to make sure that we have both hindi and english language messages sent
    l =
      Messages.list_messages(%{
        filter: %{
          body: "हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें\nTo receive messages in English, type English"
        }
      })

    assert length(l) == 3

    # Lets add checks here to make sure that we have both new contact tags recorded
    l =
      Messages.list_messages(%{
        filter: %{
          body: "हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें\nType English to receive messages in English"
        }
      })

    assert length(l) == 2

    # lets ensure we have one optout message also
    l =
      Messages.list_messages(%{
        filter: %{
          body: "भाषा बदलने के लिए, 1. दबाएँ मेनू देखने के लिए, 2 दबाएँ"
        }
      })

    assert length(l) == 1

    # lets ensure we have one help message also
    l =
      Messages.list_messages(%{
        filter: %{
          body: "भाषा बदलने के लिए, 1. दबाएँ मेनू देखने के लिए, 2 दबाएँ"
        }
      })

    assert length(l) == 1
  end
end
