defmodule Glific.Processor.ConsumerFlow do
  @moduledoc """
  Given a message, run it thru the flow engine. This is an auxilary module to help
  consumer_worker which is the main workhorse
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Flows.Periodic,
    Messages.Message,
    Repo
  }

  @doc """
  Load the relevant state into the gen_server state object that we need
  to process messages
  """
  @spec load_state(non_neg_integer) :: map()
  def load_state(organization_id) do
    flow_keywords_map =
      Flows.Flow
      |> select([:keywords, :id])
      |> where([f], f.organization_id == ^organization_id)
      |> Repo.all()
      |> Enum.reduce(%{}, fn flow, acc ->
        Enum.reduce(flow.keywords, acc, fn keyword, acc ->
          Map.put(acc, keyword, flow.id)
        end)
      end)

    %{flow_keywords: flow_keywords_map}
  end

  @doc false
  @spec process_message({Message.t(), map()}, String.t()) :: {Message.t(), map()}
  def process_message({message, state}, body) do
    context = FlowContext.active_context(message.contact_id)

    # if we are in a flow and the flow is set to ignore keywords
    # then send control to the flow directly
    # context is not nil
    with false <- is_nil(context),
         {:ok, flow} <-
           Flows.get_cached_flow(
             message.organization_id,
             context.flow_uuid,
             %{uuid: context.flow_uuid}
           ),
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
  @spec check_flows(atom() | Message.t(), String.t(), map()) :: {Message.t(), map()}
  def check_flows(message, body, state) do
    message = Repo.preload(message, :contact)
    {:ok, flow} = Flows.get_cached_flow(message.organization_id, body, %{keyword: body})
    FlowContext.init_context(flow, message.contact)
    {message, state}
  end

  @doc false
  @spec check_contexts(FlowContext.t(), atom() | Message.t(), String.t(), map()) ::
          {Message.t(), map()}
  def check_contexts(nil = _context, message, _body, state) do
    # lets do the periodic flow routine and send those out
    # in a priority order
    state = Periodic.run_flows(state, message)
    {message, state}
  end

  def check_contexts(context, message, _body, state) do
    {:ok, flow} =
      Flows.get_cached_flow(message.organization_id, context.flow_uuid, %{
        uuid: context.flow_uuid
      })

    context
    |> FlowContext.load_context(flow)
    # we are using message.body here since we want to use the original message
    # not the stripped version
    |> FlowContext.step_forward(String.trim(message.body))

    {message, state}
  end

  @doc """
  Process one context at a time that is ready to be woken
  """
  @spec wakeup(FlowContext.t(), map()) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()}
  def wakeup(context, _state) do
    # update the context woken up time as soon as possible to avoid someone else
    # grabbing this context
    {:ok, context} = FlowContext.update_flow_context(context, %{wakeup_at: nil})

    {:ok, flow} =
      Flows.get_cached_flow(context.flow.organization_id, context.flow_uuid, %{
        uuid: context.flow_uuid
      })

    {:ok, context} =
      context
      |> FlowContext.load_context(flow)
      |> FlowContext.step_forward("No Response")

    {:ok, context, []}
  end
end
