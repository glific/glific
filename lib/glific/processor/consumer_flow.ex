defmodule Glific.Processor.ConsumerFlow do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenStage

  import Ecto.Query, warn: false

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Messages.Message,
    Repo
  }

  @min_demand 0
  @max_demand 1
  @wakeup_timeout_ms 1 * 60 * 1000

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
        flows: %{}
      }
      |> reload()

    # process the wakeup queue every 1 minute
    Process.send_after(self(), :wakeup_timeout, @wakeup_timeout_ms)

    {
      :consumer,
      state,
      subscribe_to: [
        {state.producer,
         selector: fn %{type: type} -> type == :text end,
         min_demand: @min_demand,
         max_demand: @max_demand}
      ]
    }
  end

  defp reload(state) do
    flow_keywords_map =
      Flows.Flow
      |> select([:keywords, :id])
      |> Repo.all()
      |> Enum.reduce(%{}, fn flow, acc ->
        Enum.reduce(flow.keywords, acc, fn keyword, acc ->
          Map.put(acc, keyword, flow.id)
        end)
      end)

    Map.put(state, :flow_keywords, flow_keywords_map)
  end

  @doc false
  def handle_events(messages, _from, state) do
    Enum.each(messages, &process_message(&1, state))

    {:noreply, [], state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Glific.string_clean(message.body)

    message = message |> Repo.preload(:contact)

    case Map.has_key?(state.flow_keywords, body) do
      false ->
        check_contexts(message, body, state)

      true ->
        check_flows(message, body, state)
    end
  end

  @doc """
  Start a flow or reactivate a flow if needed. This will be linked to the entire
  trigger mechanism once we have that under control.
  """
  @spec check_flows(atom() | Message.t(), String.t(), map()) :: Message.t()
  def check_flows(message, body, _state) do
    message = Repo.preload(message, :contact)
    {:ok, flow} = Flows.get_cached_flow(body, %{keyword: body})
    FlowContext.init_context(flow, message.contact)
    message
  end

  @doc """
  Check contexts
  """
  @spec check_contexts(atom() | Message.t(), String.t(), map()) :: Message.t()
  def check_contexts(message, _body, _state) do
    context = FlowContext.active_context(message.contact_id)

    if context do
      {:ok, flow} = Flows.get_cached_flow(context.flow_uuid, %{uuid: context.flow_uuid})

      context
      |> FlowContext.load_context(flow)
      |> FlowContext.step_forward(message.body)
    else
      # lets  check if we should initiate the out of office flow
      # lets do this only if we've not sent them the out of office flow
      # in the past 12 hours
      if FunWithFlags.enabled?(:out_of_office_active) do
        {:ok, flow} = Flows.get_cached_flow("outofoffice", %{shortcode: "outofoffice"})

        if !Flows.flow_activated(flow.id, message.contact_id) do
          FlowContext.init_context(flow, message.contact)
        end
      end

      message
    end

    # we can potentially save the {contact_id, context} map here in the flow state,
    # to avoid hitting the DB again. We'll do this after we get this working
    message
  end

  @doc """
  This callback handles the nudges in the system. It processes the jobs and then
  sets a timer to invoke itself when done
  """
  def handle_info(:wakeup_timeout, state) do
    # check DB and process all flows that need to be woken update_in
    FlowContext.wakeup()
    |> Enum.each(fn fc -> wakeup(fc, state) end)

    Process.send_after(self(), :wakeup_timeout, @wakeup_timeout_ms)
    {:noreply, [], state}
  end

  # Process one context at a time
  @spec wakeup(FlowContext.t(), map()) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()}
  defp wakeup(context, _state) do
    {:ok, flow} = Flows.get_cached_flow(context.flow_uuid, %{uuid: context.flow_uuid})

    {:ok, context} =
      context
      |> FlowContext.load_context(flow)
      |> FlowContext.step_forward("No Response")

    # update the context woken up time
    {:ok, context} = FlowContext.update_flow_context(context, %{wakeup_at: nil})
    {:ok, context, []}
  end
end
