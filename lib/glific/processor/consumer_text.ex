defmodule Glific.Processor.ConsumerText do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenStage

  alias Glific.{
    Communications,
    Messages.Message,
    Repo,
    Taggers,
    Taggers.Keyword,
    Taggers.Numeric,
    Tags,
    Tags.Tag
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(_), do: GenStage.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc false
  def init(:ok) do
    state = %{
      producer: Glific.Processor.Producer,
      keyword_map: Keyword.get_keyword_map(),
      numeric_map: Numeric.get_numeric_map(),
      numeric_tag_id: 0
    }

    state =
      case Repo.fetch_by(Tag, %{label: "Numeric"}) do
        {:ok, tag} -> Map.put(state, :numeric_tag_id, tag.id)
        _ -> state
      end

    # Once we switch keyword to the DB, we will merge the map obtained from
    # the DB here

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn %{type: type} -> type == :text end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc """
  public endpoint for adding a number and a value
  """
  @spec add_numeric(String.t(), integer) :: :ok
  def add_numeric(key, value), do: GenServer.call(__MODULE__, {:add_numeric, {key, value}})

  @doc false
  def handle_call({:add_numeric, {key, value}}, _from, state) do
    new_numeric_map = Map.put(state.numeric_map, key, value)

    {:reply, "Numeric Map Updated", [], Map.put(state, :numeric_map, new_numeric_map)}
  end

  @doc false
  def handle_info(_, state), do: {:noreply, [], state}

  @doc false
  def handle_events(messages, _from, state) do
    _ = Enum.map(messages, &process_message(&1, state))

    {:noreply, [], state}
  end

  @spec process_message(atom() | Message.t(), map()) :: nil
  defp process_message(message, state) do
    body = Taggers.string_clean(message.body)

    case Numeric.tag_body(body, state.numeric_map) do
      {:ok, value} -> add_numeric_tag(message, value, state)
      _ -> nil
    end

    case Keyword.tag_body(body, state.keyword_map) do
      {:ok, value} -> add_keyword_tag(message, value, state)
      _ -> nil
    end
    nil
  end

  @spec add_numeric_tag(Message.t(), String.t(), atom() | map()) :: Message.t()
  defp add_numeric_tag(message, value, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.numeric_tag_id,
      value: value
    })
    # now publish the message tag event
    |> Communications.publish_data(:created_message_tag)
  end

  @spec add_keyword_tag(Message.t(), String.t(), atom() | map()) :: Message.t()
  defp add_keyword_tag(message, value, _state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: String.to_integer(value)
    })
    # now publish the message tag event
    |> Communications.publish_data(:created_message_tag)
  end
end
