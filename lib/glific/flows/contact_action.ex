defmodule Glific.Flows.ContactAction do
  @moduledoc """
  Since many of the functions, also do a few actions like send a message etc
  centralizing it here
  """

  alias Glific.{
    Contacts,
    Flows,
    Flows.Node,
    Messages,
    Messages.Message,
    Repo,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates,
    Templates.SessionTemplate
  }

  alias Glific.Flows.{Action, FlowContext, Localization, MessageVarParser}

  require Logger
  @min_delay 2
  @max_loop_limit 3
  @abort_loop_limit 4

  @doc """
  This is just a think wrapper for send_message, since its basically the same,
  but instead of sending the message to the contact, sends it to another contact
  that is identified in the action. You can send the same notification to multiple
  contacts
  """
  @spec send_broadcast(FlowContext.t(), Action.t(), [Message.t()]) :: {:ok, map(), any()}
  def send_broadcast(context, action, messages) do
    # note that we return the result of the last reduce
    # all the ones in between are ignored
    action.contacts
    |> Enum.reduce(
      {:ok, context, messages},
      fn contact, {_, _, _} ->
        {:ok, cid} = Glific.parse_maybe_integer(contact["uuid"])
        cid = Glific.Clients.broadcast(action, context.contact, cid)
        send_message(context, action, messages, cid)
      end
    )
  end

  @doc """
  Send interactive messages
  """
  @spec send_interactive_message(FlowContext.t(), Action.t(), [Message.t()]) ::
          {:ok, map(), any()}
  def send_interactive_message(context, action, messages) do
    ## We might need to think how to send the interactive message to a group
    {context, action} = process_labels(context, action)
    {cid, message_vars} = resolve_cid(context, nil)

    {:ok, interactive_template} =
      Repo.fetch_by(
        InteractiveTemplate,
        %{id: action.interactive_template_id, organization_id: context.organization_id}
      )

    interactive_content =
      interactive_template
      |> InteractiveTemplates.get_translations(context.contact.language_id)
      |> MessageVarParser.parse_map(message_vars)
      |> InteractiveTemplates.get_clean_interactive_content(
        interactive_template.send_with_title,
        interactive_template.type
      )

    body =
      InteractiveTemplates.get_interactive_body(
        interactive_content,
        interactive_content["type"],
        interactive_content["content"]["type"]
      )

    with {false, context} <- has_loops?(context, body, messages) do
      attrs = %{
        body: body,
        uuid: action.uuid,
        type: interactive_content["type"],
        receiver_id: cid,
        flow_label: action.labels,
        organization_id: context.organization_id,
        flow_id: context.flow_id,
        flow_broadcast_id: context.flow_broadcast_id,
        send_at: DateTime.add(DateTime.utc_now(), context.delay),
        is_optin_flow: Flows.is_optin_flow?(context.flow),
        interactive_template_id: action.interactive_template_id
      }

      attrs
      |> Messages.create_and_send_message()
      |> handle_message_result(context, messages, attrs)
    end
  end

  @spec has_loops?(FlowContext.t(), String.t(), [Message.t()]) ::
          {:ok, map(), any()} | {false, FlowContext.t()}
  defp has_loops?(context, body, messages) do
    {context, count} = update_recent(context, body)

    if count <= @max_loop_limit,
      do: {false, context},
      else: process_loops(context, count, messages, body)
  end

  # handle the case if we are sending a notification to another contact who is
  # staff, so we need info for both
  # the nil case is the regular case of sending a message
  @spec resolve_cid(FlowContext.t(), non_neg_integer | nil) :: tuple()
  defp resolve_cid(context, nil = _cid) do
    # Since we are saving the data after loading the flow
    # so we have to fetch the latest contact fields
    {
      context.contact_id,
      %{
        "contact" => Contacts.get_contact_field_map(context.contact_id),
        "results" => context.results,
        "flow" => %{name: context.flow.name, id: context.flow.id}
      }
    }
  end

  defp resolve_cid(context, cid),
    do: {
      cid,
      %{
        "contact" => Contacts.get_contact_field_map(context.contact_id),
        "staff" => Contacts.get_contact_field_map(cid),
        "results" => context.results
      }
    }

  @spec update_recent(FlowContext.t(), String.t()) :: {FlowContext.t(), non_neg_integer}
  defp update_recent(context, body) do
    # we'll mark that we came here and are planning to send it, even if
    # we dont end up sending it. This allows us to detect and abort infinite loops
    context = FlowContext.update_recent(context, body, :recent_outbound)

    # count the number of times we sent the same message in the recent list
    # in the past 6 hours
    count = FlowContext.match_outbound(context, body)
    {context, count}
  end

  @spec get_body(SessionTemplate.t()) :: String.t()
  defp get_body(%{body: body} = session_template) when is_nil(body) or body == "" do
    "Session Template: " <> session_template.label
  end

  defp get_body(%{body: body}), do: body

  @doc """
  If the template is not defined for the message send text messages.
  Given a shortcode and a context, send the right session template message
  to the contact.

  We also need to handle translations for template messages, since whatsapp
  gives them unique uuids
  """
  @spec send_message(FlowContext.t(), Action.t(), [Message.t()], non_neg_integer | nil) ::
          {:ok, map(), any()}
  def send_message(context, action, messages, cid \\ nil)

  def send_message(context, %Action{templating: nil} = action, messages, cid) do
    {context, action} = process_labels(context, action)
    {cid, message_vars} = resolve_cid(context, cid)

    # get the text translation if needed
    text = Localization.get_translation(context, action, :text)

    body =
      text
      |> MessageVarParser.parse(message_vars)

    with {false, context} <- has_loops?(context, body, messages) do
      do_send_message(context, action, messages, %{
        cid: cid,
        body: body,
        text: text,
        flow_label: action.labels
      })
    end
  end

  def send_message(
        context,
        %Action{templating: templating} = action,
        messages,
        cid
      ) do
    {context, action} = process_labels(context, action)
    {cid, message_vars} = resolve_cid(context, cid)

    variables = Localization.get_translated_template_vars(context, templating)
    vars = Enum.map(variables, &MessageVarParser.parse(&1, message_vars))

    session_template = Messages.parse_template_vars(templating.template, vars)

    body = get_body(session_template)

    with {false, context} <- has_loops?(context, body, messages) do
      do_send_template_message(context, action, messages, %{
        cid: cid,
        session_template: session_template,
        params: vars,
        flow_label: action.labels
      })
    end
  end

  @spec do_send_template_message(FlowContext.t(), Action.t(), [Message.t()], map()) ::
          {:ok, map(), any()}
  defp do_send_template_message(context, action, messages, %{
         cid: cid,
         session_template: session_template,
         params: params,
         flow_label: flow_label
       }) do
    attachments = Localization.get_translation(context, action, :attachments)

    {type, media_id} =
      if is_nil(attachments) or attachments == %{},
        do: {session_template.type, session_template.message_media_id},
        else: get_media_from_attachment(attachments, "", context, cid)

    session_template =
      session_template
      |> Map.merge(%{message_media_id: media_id, type: type})

    ## This is bit expansive and we will optimize it bit more
    # session_template =
    if Flows.is_media_type?(type) and media_id != nil do
      Messages.get_message_media!(media_id)
      |> Messages.update_message_media(%{caption: session_template.body})
    end

    attrs = %{
      receiver_id: cid,
      uuid: action.uuid,
      flow_id: context.flow_id,
      flow_broadcast_id: context.flow_broadcast_id,
      is_hsm: true,
      flow_label: flow_label,
      send_at: DateTime.add(DateTime.utc_now(), context.delay),
      params: params
    }

    Messages.create_and_send_session_template(session_template, attrs)
    |> handle_message_result(context, messages, attrs)
  end

  @spec process_labels(FlowContext.t(), Action.t()) :: {FlowContext.t(), Action.t()}
  defp process_labels(context, %{labels: nil} = action), do: {context, action}

  defp process_labels(context, %{labels: labels} = action) do
    flow_label =
      labels
      |> Enum.map_join(", ", fn label -> label["name"] end)

    {context, Map.put(action, :labels, flow_label)}
  end

  @spec process_loops(FlowContext.t(), non_neg_integer, [Message.t()], String.t()) ::
          {:ok, map(), any()}
  defp process_loops(context, count, messages, body) do
    if count > @abort_loop_limit do
      # this might happen when there is no Exit pathway out of the loop
      Node.infinite_loop(context, body)
    else
      # :loop_detected
      exit_loop(context, messages)
    end
  end

  @spec exit_loop(FlowContext.t(), [Message.t()]) ::
          {:ok, map(), any()}
  defp exit_loop(context, messages) do
    {:ok, context,
     [Messages.create_temp_message(context.organization_id, "Exit Loop") | messages]}
  end

  @spec do_send_message(FlowContext.t(), Action.t(), [Message.t()], map()) ::
          {:ok, map(), any()}
  defp do_send_message(
         context,
         action,
         messages,
         %{
           body: body,
           text: text,
           cid: cid,
           flow_label: flow_label
         }
       ) do
    organization_id = context.organization_id

    attachments = Localization.get_translation(context, action, :attachments)

    {type, media_id} = get_media_from_attachment(attachments, text, context, cid)

    attrs = %{
      uuid: action.uuid,
      body: body,
      type: type,
      media_id: media_id,
      receiver_id: cid,
      organization_id: organization_id,
      flow_label: flow_label,
      flow_id: context.flow_id,
      flow_broadcast_id: context.flow_broadcast_id,
      send_at: DateTime.add(DateTime.utc_now(), context.delay),
      is_optin_flow: Flows.is_optin_flow?(context.flow)
    }

    attrs
    |> Messages.create_and_send_message()
    |> handle_message_result(context, messages, attrs)
  end

  defp handle_message_result(result, context, messages, attrs) do
    case result do
      {:ok, _message} ->
        {:ok, %{context | delay: context.delay + @min_delay}, messages}

      {:error, error} ->
        error(context, error, attrs)
    end
  end

  @spec error(FlowContext.t(), any(), map()) :: {:ok, map(), any()}
  defp error(context, error, attrs) do
    message = "Error sending message, resetting context: #{inspect(error)}, #{inspect(attrs)}"

    # returning for now, but resetting the context
    context = FlowContext.reset_all_contexts(context, message)
    {:ok, context, []}
  end

  @spec get_media_from_attachment(any(), any(), FlowContext.t(), non_neg_integer()) :: any()
  defp get_media_from_attachment(attachment, _, _, _)
       when attachment == %{} or is_nil(attachment),
       do: {:text, nil}

  defp get_media_from_attachment(attachment, caption, context, cid) do
    [type | _tail] = Map.keys(attachment)
    url = String.trim(attachment[type])

    {type, url} = handle_attachment_expression(context, type, url)

    type = Glific.safe_string_to_atom(type)

    {_cid, message_vars} = resolve_cid(context, cid)

    {:ok, message_media} =
      %{
        type: type,
        url: url,
        source_url: url,
        thumbnail: url,
        caption: MessageVarParser.parse(caption, message_vars),
        organization_id: context.organization_id
      }
      |> Messages.create_message_media()

    {type, message_media.id}
  end

  @spec handle_attachment_expression(FlowContext.t(), String.t(), String.t()) :: tuple()
  defp handle_attachment_expression(context, "expression", expression),
    do:
      FlowContext.parse_context_string(context, expression)
      |> Glific.execute_eex()
      |> Messages.get_media_type_from_url()

  defp handle_attachment_expression(_context, type, url),
    do: {type, url}

  @doc """
  Contact opts in via a flow
  """
  @spec optin(FlowContext.t(), Keyword.t()) :: FlowContext.t()
  def optin(context, opts \\ []) do
    # We need to update the contact with optout_time and status
    Contacts.contact_opted_in(
      context.contact.phone,
      context.contact.organization_id,
      DateTime.utc_now(),
      Keyword.put(opts, :optin_on_bsp, true)
    )

    context
  end

  @doc """
  Contact opts out
  """
  @spec optout(FlowContext.t()) :: FlowContext.t()
  def optout(context) do
    # We need to update the contact with optout_time and status
    Contacts.contact_opted_out(
      context.contact.phone,
      context.contact.organization_id,
      DateTime.utc_now(),
      # at some point we might want to add flow name
      "Glific Flows"
    )

    context
  end
end
