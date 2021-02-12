defmodule Glific.Flows.ContactAction do
  @moduledoc """
  Since many of the functions, also do a few actions like send a message etc
  centralizing it here
  """

  alias Glific.{
    Contacts,
    Flows.Action,
    Flows.FlowContext,
    Flows.Localization,
    Flows.MessageVarParser,
    Messages,
    Messages.Message
  }

  require Logger
  @min_delay 2

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
        send_message(context, action, messages, cid)
      end
    )
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
        "results" => context.results
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
    {cid, message_vars} = resolve_cid(context, cid)

    # get the text translation if needed
    text = Localization.get_translation(context, action, :text)

    body =
      text
      |> MessageVarParser.parse(message_vars)
      |> MessageVarParser.parse_results(context.results)

    # we'll mark that we came here and are planning to send it, even if
    # we dont end up sending it. This allows us to detect and abort infinite loops
    context = FlowContext.update_recent(context, body, :recent_outbound)

    # count the number of times we sent the same message in the recent list
    # in the past 6 hours
    count = FlowContext.match_outbound(context, body)

    cond do
      # this might happen when there is no Exit pathway out of the loop
      count > 5 ->
        infinite_loop(context, body)

      # :loop_detected
      count == 5 ->
        exit_loop(context, messages)

      true ->
        do_send_message(context, action, messages, %{
          cid: cid,
          body: body,
          text: text,
        })
    end
  end

  def send_message(
        context,
        %Action{templating: templating} = action,
        messages,
        cid
      ) do
    {cid, message_vars} = resolve_cid(context, cid)

    vars = Enum.map(templating.variables, &MessageVarParser.parse(&1, message_vars))

    session_template = Messages.parse_template_vars(templating.template, vars)

    attachments = Localization.get_translation(context, action, :attachments)

    {type, media_id} =
      if is_nil(attachments) or attachments == %{},
        do: {session_template.type, session_template.message_media_id},
        else: get_media_from_attachment(attachments, "", context.organization_id)

    session_template =
      session_template
      |> Map.merge(%{message_media_id: media_id, type: type})

    ## This is bit expansive and we will optimize it bit more
    # session_template =
    if type in [:image, :video, :audio] and media_id != nil do
      Messages.get_message_media!(media_id)
      |> Messages.update_message_media(%{caption: session_template.body})
    end

    {:ok, _message} =
      Messages.create_and_send_session_template(
        session_template,
        %{
          receiver_id: cid,
          flow_id: context.flow_id,
          is_hsm: true,
          send_at: DateTime.add(DateTime.utc_now(), context.delay)
        }
      )

    # increment the delay
    {:ok, %{context | delay: context.delay + @min_delay}, messages}
  end

  @spec infinite_loop(FlowContext.t(), String.t()) ::
          {:ok, map(), any()}
  defp infinite_loop(context, body) do
    Logger.info("Infinite loop detected, body: #{body}. Resetting context")
    FlowContext.reset_context(context)

    # at some point soon, we should change action signatures to allow error
    {:ok, context, []}
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
           cid: cid
         }
       ) do
    organization_id = context.organization_id

    attachments = Localization.get_translation(context, action, :attachments)
    {type, media_id} = get_media_from_attachment(attachments, text, organization_id)

    attrs = %{
      uuid: action.uuid,
      body: body,
      type: type,
      media_id: media_id,
      receiver_id: cid,
      organization_id: organization_id,
      flow_id: context.flow_id,
      send_at: DateTime.add(DateTime.utc_now(), context.delay)
    }

    Messages.create_and_send_message(attrs)
    |> case do
      {:ok, _message} ->
        {:ok, %{context | delay: context.delay + @min_delay}, messages}

      {:error, error} ->
        Logger.info("Error sending message: #{inspect(error)}, #{inspect(attrs)}")
        # returning for now, but resetting the context
        FlowContext.reset_context(context)
        {:ok, context, []}
    end
  end

  @spec get_media_from_attachment(any(), any(), non_neg_integer()) :: any()
  defp get_media_from_attachment(attachment, _, _) when attachment == %{} or is_nil(attachment),
    do: {:text, nil}

  defp get_media_from_attachment(attachment, caption, organization_id) do
    [type | _tail] = Map.keys(attachment)

    url =
      attachment[type]
      |> String.trim()

    type = Glific.safe_string_to_atom(type)

    {:ok, message_media} =
      %{
        type: type,
        url: url,
        source_url: url,
        thumbnail: url,
        caption: caption,
        organization_id: organization_id
      }
      |> Messages.create_message_media()

    {type, message_media.id}
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
      DateTime.utc_now()
    )

    context
  end
end
