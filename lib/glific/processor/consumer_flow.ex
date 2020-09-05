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
    Flows.Periodic,
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
    wakeup_timeout = Keyword.get(opts, :wakeup_timeout, @wakeup_timeout_ms)

    GenStage.start_link(__MODULE__, [producer: producer, wakeup_timeout: wakeup_timeout], name: name)
  end

  @doc false
  def init(opts) do
    state =
      %{
        producer: opts[:producer],
        wakeup_timeout: opts[:wakeup_timeout],
        flows: %{},
      }
      |> reload()

    # process the wakeup queue every 1 minute
    Process.send_after(self(), :wakeup_timeout, state[:wakeup_timeout])

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
    state =
      Enum.reduce(
        messages,
        state,
        fn message, state ->
          {state, _message} = process_message(state, message)
          state
        end
      )

    {:noreply, [], state}
  end

  @spec process_message(map(), Message.t()) :: {map(), Message.t()}
  defp process_message(state, message) do
    body = Glific.string_clean(message.body)

    message = message |> Repo.preload(:contact)

    context = FlowContext.active_context(message.contact_id)

    # if we are in a flow and the flow is setto ignore keywords
    # then send control to the flow directly
    with false <- is_nil(context),
         {:ok, flow} <- Flows.get_cached_flow(context.flow_uuid, %{uuid: context.flow_uuid}),
         true <- flow.ignore_keywords do
      check_contexts(context, message, body, state)
    else
      _ ->
        if Map.has_key?(state.flow_keywords, body),
          do: check_flows(message, body, state),
          else: check_contexts(context, message, body, state)
    end
  end

  @doc """
  Start a flow or reactivate a flow if needed. This will be linked to the entire
  trigger mechanism once we have that under control.
  """
  @spec check_flows(atom() | Message.t(), String.t(), map()) :: {map(), Message.t()}
  def check_flows(message, body, state) do
    message = Repo.preload(message, :contact)
    {:ok, flow} = Flows.get_cached_flow(body, %{keyword: body})
    FlowContext.init_context(flow, message.contact)
    {state, message}
  end

  @doc false
  @spec check_contexts(FlowContext.t(), atom() | Message.t(), String.t(), map()) ::
          {map(), Message.t()}
  def check_contexts(nil = _context, message, _body, state) do
    # lets do the periodic flow routine and send those out
    # in a priority order
    state = Periodic.run_flows(state, message)
    {state, message}
  end

  def check_contexts(context, message, _body, state) do
    {:ok, flow} = Flows.get_cached_flow(context.flow_uuid, %{uuid: context.flow_uuid})

    context
    |> FlowContext.load_context(flow)
    # we are using message.body here since we want to use the original message
    # not the stripped version
    |> FlowContext.step_forward(String.trim(message.body))

    {state, message}
  end

  @doc """
  This callback handles the nudges in the system. It processes the jobs and then
  sets a timer to invoke itself when done
  """
  def handle_info(:wakeup_timeout, state) do
    # check DB and process all flows that need to be woken update_in
    FlowContext.wakeup()
    |> Enum.each(fn fc -> wakeup(fc, state) end)

    Process.send_after(self(), :wakeup_timeout, state[:wakeup_timeout])
    {:noreply, [], state}
  end

  # Process one context at a time
  @spec wakeup(FlowContext.t(), map()) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()}
  defp wakeup(context, _state) do
    # update the context woken up time as soon as possible to avoid someone else
    # grabbing this context
    {:ok, context} = FlowContext.update_flow_context(context, %{wakeup_at: nil})

    {:ok, flow} = Flows.get_cached_flow(context.flow_uuid, %{uuid: context.flow_uuid})

    {:ok, context} =
      context
      |> FlowContext.load_context(flow)
      |> FlowContext.step_forward("No Response")

    {:ok, context, []}
  end
end
