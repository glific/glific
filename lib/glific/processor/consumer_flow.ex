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
    Messages,
    Messages.Message
  }

  @doc """
  Load the relevant state into the gen_server state object that we need
  to process messages
  """
  @spec load_state(non_neg_integer) :: map()
  def load_state(organization_id), do: %{flow_keywords: Flows.flow_keywords_map(organization_id)}

  @doc false
  @spec process_message({Message.t(), map()}, String.t()) :: {Message.t(), map()}
  def process_message({message, state}, body) do
    if should_skip_flow?(message),
      do: {message, state},
      else: do_process_message({message, state}, body)
  end

  @spec do_process_message({Message.t(), map()}, String.t()) :: {Message.t(), map()}
  defp do_process_message({message, state}, body) do
    context = FlowContext.active_context(message.contact_id)
    # if we are in a flow and the flow is set to ignore keywords
    # then send control to the flow directly
    # context is not nil
    with false <- is_nil(context),
         {:ok, flow} <-
           Flows.get_cached_flow(
             message.organization_id,
             {:flow_uuid, context.flow_uuid},
             %{uuid: context.flow_uuid}
           ),
         true <- flow.ignore_keywords do
      check_contexts(context, message, body, state)
    else
      _ ->
        cond do
          Map.get(state, :newcontact, false) == true -> check_flows(message, "newcontact", state)
          Map.has_key?(state.flow_keywords, body) -> check_flows(message, body, state)
          true -> check_contexts(context, message, body, state)
        end
    end
  end

  @doc """
  Start a flow or reactivate a flow if needed. This will be linked to the entire
  trigger mechanism once we have that under control.
  """
  @spec check_flows(atom() | Message.t(), String.t(), map()) :: {Message.t(), map()}
  def check_flows(message, body, state) do
    {:ok, flow} =
      Flows.get_cached_flow(message.organization_id, {:flow_keyword, body}, %{keyword: body})

    FlowContext.init_context(flow, message.contact)
    {message, state}
  end

  @doc false
  @spec check_contexts(FlowContext.t() | nil, atom() | Message.t(), String.t(), map()) ::
          {Message.t(), map()}
  def check_contexts(nil = _context, message, _body, state) do
    # lets do the periodic flow routine and send those out
    # in a priority order
    state = Periodic.run_flows(state, message)
    {message, state}
  end

  def check_contexts(context, message, _body, state) do
    {:ok, flow} =
      Flows.get_cached_flow(message.organization_id, {:flow_uuid, context.flow_uuid}, %{
        uuid: context.flow_uuid
      })

    context
    |> Map.merge(%{last_message: message})
    |> FlowContext.load_context(flow)
    # we are using message.body here since we want to use the original message
    # not the stripped version
    |> FlowContext.step_forward(
      Messages.create_temp_message(
        message.organization_id,
        message.body,
        type: message.type,
        id: message.id
      )
    )

    {message, state}
  end

  # if this is a new contact then we will allow to
  # process the flow other wise system will check if
  # they opted in again and skip the flow
  @spec should_skip_flow?(Message.t()) :: boolean()
  defp should_skip_flow?(message) do
    message = Glific.Repo.preload(message, [:tags])

    is_new_contact =
      message.tags
      |> Enum.any?(fn tag -> tag.shortcode == "newcontact" end)

    if is_new_contact and message.body == nil,
      do: false,
      else: String.contains?(message.body, "Hi, I would like to receive notifications.")
  end
end
