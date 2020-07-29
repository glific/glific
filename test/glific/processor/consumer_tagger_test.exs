defmodule TestProducer do
  use GenStage

  alias Glific.{
    Fixtures,
    Processor.ConsumerTagger,
    Repo,
    Tags
  }

  @checks %{
    0 => {"shunya", "Numeric", "0"},
    1 => {"12", "Numeric", "12"},
    2 => {"hindi", "Language", nil},
    3 => {"english", "Language", nil},
    4 => {"hello", "Greeting", nil},
    5 => {"bye", "Good Bye", nil},
    6 => {"thanks", "Thank You", nil},
    7 => {"ek", "Numeric", "1"},
    8 => {"हिंदी", "Language", nil},
    9 => {to_string(['\u0039', 65_039, 8419]), "Numeric", "9"}
  }

  @doc false
  @spec get_checks() :: %{integer => {}}
  def get_checks, do: @checks

  def start_link(demand) do
    GenStage.start_link(__MODULE__, demand, name: TestProducer)
  end

  def init(demand), do: {:producer, demand}

  def handle_demand(demand, counter) when counter > 10 do
    send(:test, {:called_back})
    {:stop, :normal, demand}
  end

  def handle_demand(demand, counter) when demand > 0 do
    events =
      Enum.map(
        counter..(counter + demand - 1),
        fn c -> Fixtures.message_fixture(%{body: elem(@checks[rem(c, 10)], 0)}) end
      )

    {:noreply, events, demand + counter}
  end
end

defmodule Glific.Processor.ConsumerTaggerTest do
  use Glific.DataCase

  alias Glific.{
    Processor.ConsumerTagger,
    Repo,
    Seeds.SeedsDev,
    Tags,
    Tags.MessageTag
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    SeedsDev.seed_session_templates()
    :ok
  end

  test "should behave like consumer" do
    {:ok, producer} = TestProducer.start_link(1)
    {:ok, _consumer} = ConsumerTagger.start_link(producer: producer, name: TestConsumerTagger)

    Process.register(self(), :test)
    assert_receive({:called_back}, 10000)

    # ensure we have a few message tags in the DB
    assert Repo.aggregate(MessageTag, :count) > 0

    # check the message tags
    tags = ["Language", "Unread", "Greeting", "Thank You", "Numeric", "Good Bye"]
    tag_ids = Tags.tags_map(tags)

    Enum.map(
      TestProducer.get_checks(),
      # ensure that a tag with that value exists in the DB
      fn
        {_, {_, tag, nil}} ->
          {:ok, result} =
            Repo.query(
              """
              SELECT count(*) FROM messages_tags
              WHERE tag_id = $1
              """,
              [tag_ids[tag]]
            )

          [[count]] = result.rows
          assert count > 0

        {_, {_, tag, value}} ->
          {:ok, result} =
            Repo.query(
              """
              SELECT count(*) FROM messages_tags
              WHERE tag_id = $1 AND value = $2
              """,
              [tag_ids[tag], value]
            )

          [[count]] = result.rows
          assert count > 0
      end
    )
  end
end
