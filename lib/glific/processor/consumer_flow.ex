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
    Messages.Message,
    Partners
  }

  @doc """
  Load the relevant state into the gen_server state object that we need
  to process messages
  """
  @spec load_state(non_neg_integer) :: map()
  def load_state(organization_id) do
    %{
      flow_keywords: Flows.flow_keywords_map(organization_id),
      regx_flow: Partners.organization(organization_id).regx_flow
    }
  end

  @doc false
  @spec process_message({Message.t(), map()}, String.t()) :: {Message.t(), map()}
  def process_message({message, state}, body) do
    # check if draft keyword, if so bypass ignore keywords
    # and start draft flow, issue #621
    is_draft = is_draft_keyword?(state, body)

    if is_draft,
      do:
        FlowContext.mark_flows_complete(message.contact_id, false,
          source: "process_message",
          event_meta: %{
            is_draft: is_draft,
            body: body
          }
        )

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
  @draft_phrase "draft"
  @final_phrase "published"
  @optin_flow_keyword "optin"

  @doc """
  In case contact is not in optin flow let's move ahead with the regular processing.
  """
  @spec move_forward({Message.t(), map()}, String.t(), FlowContext.t(), Keyword.t()) ::
          {Message.t(), map()}
  def move_forward({message, state}, body, context, opts) do
    cond do
      continue_the_context?(context) ->
        continue_current_context(context, message, body, state)

      start_new_contact_flow?(state) ->
        flow_id = state.flow_keywords["org_default_new_contact"]
        flow_params = {:flow_id, flow_id, @final_phrase}
        start_new_flow(message, body, state, delay: @delay_time, flow_params: flow_params)

      is_flow_keyword?(state, body) ->
        flow_params = {:flow_keyword, body, @final_phrase}
        start_new_flow(message, body, state, flow_params: flow_params)

      Keyword.get(opts, :is_draft, false) ->
        body = String.replace_leading(message.body, @draft_phrase <> ":", "")
        flow_params = {:flow_keyword, body, @draft_phrase}
        opts = [status: @draft_phrase, flow_params: flow_params]
        start_new_flow(message, message.body, state, opts)

      # making sure that user is not in any flow.
      is_context_nil?(context) && match_with_regex?(state.regx_flow, message.body) ->
        flow_id = Glific.parse_maybe_integer!(state.regx_flow.flow_id)
        flow_params = {:flow_id, flow_id, @final_phrase}
        start_new_flow(message, body, state, delay: @delay_time, flow_params: flow_params)

      is_context_nil?(context) ->
        state = Periodic.run_flows(state, message)
        {message, state}

      true ->
        continue_current_context(context, message, body, state)
    end
  end

  @doc """
  Start a flow or reactivate a flow if needed. This will be linked to the entire
  trigger mechanism once we have that under control.
  """
  @spec start_new_flow(atom() | Message.t(), String.t(), map(), Keyword.t()) ::
          {Message.t(), map()}
  def start_new_flow(message, _body, state, opts \\ []) do
    flow_params = Keyword.get(opts, :flow_params, nil)
    status = Keyword.get(opts, :status, @final_phrase)

    Flows.get_cached_flow(message.organization_id, flow_params)
    |> case do
      {:ok, flow} ->
        opts = Keyword.put(opts, :flow_keyword, message.body)
        FlowContext.init_context(flow, message.contact, status, opts)

      {:error, _} ->
        nil
    end

    {message, state}
  end

  @doc false
  @spec continue_current_context(
          FlowContext.t() | nil,
          atom() | Message.t(),
          String.t(),
          map()
        ) ::
          {Message.t(), map()}
  def continue_current_context(context, message, _body, state) do
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
        location: message.location,
        interactive_content: message.interactive_content
      )
    )

    {message, state}
  end

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
    FlowContext.mark_flows_complete(message.contact_id, false,
      source: "start_optin_flow",
      event_meta: %{
        message_id: message.id
      }
    )

    flow_id = state.flow_keywords["org_default_optin"]

    args =
      if flow_id,
        do: {:flow_id, flow_id, @final_phrase},
        else: {:flow_keyword, @optin_flow_keyword, @final_phrase}

    Flows.get_cached_flow(
      message.organization_id,
      args
    )
    |> case do
      {:ok, flow} ->
        FlowContext.init_context(flow, message.contact, @final_phrase, is_draft: false)

      {:error, _} ->
        nil
    end

    {message, state}
  end

  @spec start_new_contact_flow?(map()) :: boolean()
  defp start_new_contact_flow?(state) do
    Map.get(state, :newcontact, false) && !is_nil(state.flow_keywords["org_default_new_contact"])
  end

  @spec is_flow_keyword?(map(), String.t()) :: boolean()
  defp is_flow_keyword?(state, body) do
    Map.has_key?(state.flow_keywords["published"], body)
  end

  @spec match_with_regex?(map(), String.t()) :: boolean()
  defp match_with_regex?(regx_flow, body) when nil in [regx_flow, body], do: false

  defp match_with_regex?(regx_flow, body) when is_map(regx_flow) == true do
    Regex.compile(regx_flow.regx, regx_flow.regx_opt)
    |> case do
      {:ok, rgx} -> String.match?(body, rgx)
      _ -> false
    end
  end

  defp match_with_regex?(_, _), do: false

  @spec continue_the_context?(FlowContext.t()) :: boolean()
  defp continue_the_context?(context) do
    cond do
      is_nil(context) -> false
      context.flow.ignore_keywords -> true
      true -> false
    end
  end

  @spec is_context_nil?(FlowContext.t() | nil) :: boolean()
  ## not sure why this is giving dialyzer error. Ignoring for now
  defp is_context_nil?(context), do: is_nil(context)
end
