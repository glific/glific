defmodule Glific.Processor.ConsumerFlow do
  @moduledoc """
  Given a message, run it thru the flow engine. This is an auxilary module to help
  consumer_worker which is the main workhorse
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
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
    # check if draft keyword, if so bypass ignore keywords
    # and start draft flow, issue #621
    is_draft = is_draft_keyword?(state, body)

    if is_draft,
      do: FlowContext.mark_flows_complete(message.contact_id, false)

    context = FlowContext.active_context(message.contact_id)

    # if contact is not optout if we are in a flow and the flow is set to ignore keywords
    # then send control to the flow directly
    # context is not nil

    if start_optin_flow?(message.contact, context, body),
      do: start_optin_flow(message, state),
      else: move_forward({message, state}, body, context, is_draft: is_draft)
  end

  # Setting this to 0 since we are pushing out our own optin flow
  @delay_time 0

  @doc """
  In case contact is not in optin flow let's move ahead with the regualr processing.
  """
  @spec move_forward({Message.t(), map()}, String.t(), FlowContext.t(), Keyword.t()) ::
          {Message.t(), map()}
  def move_forward({message, state}, body, context, opts) do
    with false <- is_nil(context),
         {:ok, flow} <-
           Flows.get_cached_flow(
             message.organization_id,
             {:flow_uuid, context.flow_uuid, context.status}
           ),
         true <- flow.ignore_keywords do
      check_contexts(context, message, body, state)
    else
      _ ->
        cond do
          Map.get(state, :newcontact, false) &&
              !is_nil(state.flow_keywords["new_contact"]) ->
            # delay new contact flows by 2 minutes to allow user to deal with signon link
            flow_id = state.flow_keywords["new_contact"]

            check_flows(message, body, state,
              is_newcontact: true,
              flow_id: flow_id,
              delay: @delay_time
            )

          Map.has_key?(state.flow_keywords["published"], body) ->
            check_flows(message, body, state)

          Keyword.get(opts, :is_draft, false) ->
            check_flows(message, message.body, state, is_draft: true)

          true ->
            check_contexts(context, message, body, state)
        end
    end
  end

  @draft_phrase "draft"
  @final_phrase "published"

  @spec is_draft_keyword?(map(), String.t()) :: boolean()
  defp is_draft_keyword?(_state, nil), do: false

  defp is_draft_keyword?(state, body) do
    if String.starts_with?(body, @draft_phrase) and
         Map.has_key?(
           state.flow_keywords["draft"],
           String.replace_leading(body, @draft_phrase, "")
         ),
       do: true,
       else: false
  end

  @doc """
  Start a flow or reactivate a flow if needed. This will be linked to the entire
  trigger mechanism once we have that under control.
  """
  @spec check_flows(atom() | Message.t(), String.t(), map(), Keyword.t()) :: {Message.t(), map()}
  def check_flows(message, body, state, opts \\ []) do
    is_draft = Keyword.get(opts, :is_draft, false)
    is_newcontact = Keyword.get(opts, :is_newcontact, false)
    flow_id = Keyword.get(opts, :flow_id, nil)

    {status, body} =
      if is_draft do
        # lets complete all existing flows for this contact
        {@draft_phrase, String.replace_leading(body, @draft_phrase <> ":", "")}
      else
        {@final_phrase, body}
      end

    get_cached_flow(
      is_newcontact,
      message.organization_id,
      {:flow_keyword, body, status},
      flow_id
    )
    |> case do
      {:ok, flow} ->
        FlowContext.init_context(flow, message.contact, status, opts)

      {:error, _} ->
        nil
    end

    {message, state}
  end

  defp get_cached_flow(false, organization_id, params, _flow_id),
    do: Flows.get_cached_flow(organization_id, params)

  defp get_cached_flow(true, organization_id, _params, flow_id),
    do: Flows.get_cached_flow(organization_id, {:flow_id, flow_id, @final_phrase})

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
      Flows.get_cached_flow(
        message.organization_id,
        {:flow_uuid, context.flow_uuid, context.status}
      )

    {:ok, message} =
      message
      |> Messages.update_message(%{flow_id: context.flow_id})

    context
    |> Map.merge(%{last_message: message})
    |> FlowContext.load_context(flow)
    # we are using message.body here since we want to use the original message
    # not the stripped version
    # I'm not sure why we are creating a message here instead of reusing the existing
    # message. We'll switch this to using message in the next release (1.0.1)
    |> FlowContext.step_forward(
      Messages.create_temp_message(
        message.organization_id,
        message.body,
        type: message.type,
        id: message.id,
        media: message.media,
        media_id: message.media_id,
        location: message.location
      )
    )

    {message, state}
  end

  @optin_flow_keyword "optin"

  ## check if contact is not in the optin flow and has optout time
  @spec start_optin_flow?(Contact.t(), FlowContext.t() | nil, String.t()) :: boolean()
  defp start_optin_flow?(contact, nil, _body),
    do: !is_nil(contact.optout_time)

  defp start_optin_flow?(contact, active_context, body),
    do:
      if(Flows.is_optin_flow?(active_context.flow),
        do: false,
        else: start_optin_flow?(contact, nil, body)
      )

  @spec start_optin_flow(Message.t(), map()) :: {Message.t(), map()}
  defp start_optin_flow(message, state) do
    ## remove all the previous flow context
    FlowContext.mark_flows_complete(message.contact_id, false)

    Flows.get_cached_flow(
      message.organization_id,
      {:flow_keyword, @optin_flow_keyword, @final_phrase}
    )
    |> case do
      {:ok, flow} ->
        FlowContext.init_context(flow, message.contact, @final_phrase, is_draft: false)

      {:error, _} ->
        nil
    end

    {message, state}
  end
end
