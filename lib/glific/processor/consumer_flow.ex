defmodule Glific.Processor.ConsumerFlow do
  @moduledoc """
  Process all messages of type consumer and run them thru the various flows
  At a later stage, we will separate the flows depending on various conditions
  (not sure of it as yet)
  """

  use GenStage

  alias Glific.{
    Flows.Flow,
    Flows.FlowContext,
    Messages.Message
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    producer = Keyword.get(opts, :producer, Glific.Processor.Producer)
    GenStage.start_link(__MODULE__, [producer: producer], name: name)
  end

  @doc false
  def init(opts) do
    state =
      %{
        producer: opts[:producer],
        flow_help: nil,
        flow_language: nil,
        flow_preferences: nil
      }
      |> reload

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn %{type: type} -> type == :text end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  defp reload(state) do
    {help, language, preference, new_contact} = {
      Flow.load_flow("help"),
      Flow.load_flow("language"),
      Flow.load_flow("preference"),
      Flow.load_flow("new_contact")
    }

    flows =
      if is_nil(help),
        do: %{},
        else: %{
          help.id => help,
          language.id => language,
          preference.id => preference,
          new_contact.id => new_contact
        }

    state
    |> Map.put(:flow_help, help)
    |> Map.put(:flow_language, language)
    |> Map.put(:flow_preference, preference)
    |> Map.put(:flows, flows)
  end

  @doc false
  def handle_events(messages, _from, state) do
    _ = Enum.map(messages, &process_message(&1, state))

    {:noreply, [], state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()

  defp process_message(message, state) do
    case FlowContext.active_context(message.contact_id) do
      nil ->
        message

      context ->
        context
        |> FlowContext.load_context(state.flows[context.flow_id])
        |> FlowContext.step_forward(message.body)

        # we can potentially save the {contact_id, context} map here, to avoid
        # hitting the DB again. We'll do this after we get this working
        message
    end
  end
end
