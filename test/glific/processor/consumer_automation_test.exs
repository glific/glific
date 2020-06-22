defmodule TestConsumerTagger do
  use GenStage

  alias Glific.{
    Fixtures,
    Processor.ConsumerAutomation,
    Repo,
    Settings.Language,
    Tags
  }

  def start_link(demand) do
    GenStage.start_link(__MODULE__, demand, name: TestConsumerTagger)
  end

  def init(demand) do
    tag_ids = Tags.tags_map(["New Contact", "Language"])
    language_ids = Repo.label_id_map(Language, ["Hindi", "English (United States)"])

    state = %{
      counter: demand,
      new_contact_tag_id: tag_ids["New Contact"],
      language_tag_id: tag_ids["Language"],
      language_id: language_ids["Hindi"]
    }

    {:producer, state}
  end

  defp create_message_new_contact(%{
         new_contact_tag_id: new_contact_tag_id,
         language_id: language_id
       }) do
    m =
      Fixtures.message_fixture(%{body: "This is a random first message", language_id: language_id})

    {:ok, _} = Tags.create_message_tag(%{message_id: m.id, tag_id: new_contact_tag_id})

    Repo.preload(m, :tags)
  end

  defp create_message_language(
         %{language_tag_id: language_tag_id, language_id: language_id},
         value
       ) do
    m =
      Fixtures.message_fixture(%{body: "This is a random first message", language_id: language_id})

    {:ok, _} = Tags.create_message_tag(%{message_id: m.id, tag_id: language_tag_id, value: value})

    Repo.preload(m, :tags)
  end

  def handle_demand(_demand, %{counter: counter} = state) when counter > 5 do
    send(:test, {:called_back})
    {:stop, :normal, state}
  end

  def handle_demand(demand, %{counter: counter} = state) when demand > 0 do
    events =
      Enum.map(
        counter..(counter + demand - 1),
        fn c ->
          case rem(c, 5) do
            0 -> create_message_language(state, "hindi")
            1 -> create_message_language(state, "english")
            2 -> create_message_new_contact(state)
            3 -> create_message_language(state, "हिंदी")
            4 -> create_message_new_contact(state)
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

    Process.register(self(), :test)
    assert_receive({:called_back}, 1000)

    # ensure we have a few more messages in the DB
    assert Repo.aggregate(Message, :count) > original_count

    # Lets add checks here to make sure that we have both hindi and english language messages sent
    l =
      Messages.list_messages(%{
        filter: %{
          body: "हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें\nType English to receive messages in English"
        }
      })

    # since we sent 5 messages, all of which send the language chooser message
    assert length(l) == 5
  end
end
