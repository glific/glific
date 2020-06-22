defmodule TestConsumer do
  use GenStage

  def start_link(producer) do
    GenStage.start_link(__MODULE__, {producer, self()})
  end

  def init({producer, owner}) do
    {:consumer, owner,
     subscribe_to: [
       {producer, selector: fn %{type: type} -> type == :text end}
     ]}
  end

  def handle_events(events, _from, owner) do
    send(owner, {:received, events})
    {:noreply, [], owner}
  end
end

defmodule Glific.Processor.ProducerTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Processor.Producer
  }

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    Glific.Seeds.seed_session_templates(lang)
    :ok
  end

  test "Lets test that the consumer gets text messages only" do
    {:ok, stage} = Producer.start_link(name: TestProducer)
    {:ok, _cons} = TestConsumer.start_link(stage)

    body = ["12", "hindi", "hello"]

    Enum.map(
      body,
      fn txt ->
        msg = Fixtures.message_fixture(%{body: txt})
        # now add this to the processor queue
        GenServer.cast(stage, {:add, [msg]})
        assert_receive {:received, events}
        assert length(events) == 1
      end
    )

    # lets do multiple messages at once
    msgs =
      Enum.map(
        body,
        fn txt ->
          Fixtures.message_fixture(%{body: txt})
        end
      )

    GenServer.cast(stage, {:add, msgs})
    assert_receive {:received, events}
    assert length(events) == length(body)

    GenStage.stop(stage)
  end
end
