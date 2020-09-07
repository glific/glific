defmodule TestProducer do
  use GenStage

  alias Glific.{
    Fixtures,
    Processor.ConsumerTagger,
    Repo,
    Tags.Tag,
  }

  @checks %{
    0 => {"shunya", "numeric", "0"},
    1 => {"12", "numeric", "12"},
    2 => {"hindi", "language", nil},
    3 => {"english", "language", nil},
    4 => {"hello", "greeting", nil},
    5 => {"bye", "goodbye", nil},
    6 => {"thanks", "thankyou", nil},
    7 => {"ek", "numeric", "1"},
    8 => {"हिंदी", "language", nil},
    9 => {to_string(['\u0039', 65_039, 8419]), "numeric", "9"},
    10 => {"hey there", "greeting", nil}
  }

  @checks_size Enum.count(@checks)

  @doc false
  @spec get_checks() :: %{integer => {}}
  def get_checks, do: @checks

  def start_link(demand) do
    GenStage.start_link(__MODULE__, demand, name: TestProducer)
  end

  def init(demand), do: {:producer, demand}

  def handle_demand(demand, counter) when counter > @checks_size + 1 do
    send(:test, {:called_back})
    {:stop, :normal, demand}
  end

  def handle_demand(demand, counter) when demand > 0 do
    events =
      Enum.map(
        counter..(counter + demand - 1),
        fn c -> Fixtures.message_fixture(%{body: elem(@checks[rem(c, @checks_size)], 0)}) end
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
    :ok
  end

  @tag :pending
  test "should behave like consumer",
       %{organization_id: organization_id} do
    {:ok, producer} = TestProducer.start_link(1)
    {:ok, _consumer} = ConsumerTagger.start_link(producer: producer, name: TestConsumerTagger)

    Process.register(self(), :test)
    assert_receive({:called_back}, 10_000)

    # ensure we have a few message tags in the DB
    assert Repo.aggregate(MessageTag, :count) > 0

    # check the message tags
    tags = ["language", "unread", "greeting", "thankyou", "numeric", "goodbye"]

    tag_ids =
      Repo.label_id_map(
        Tag,
        tags,
        organization_id,
        :shortcode
      )

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
