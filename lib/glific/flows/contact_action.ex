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
    Messages.Message,
    Repo
  }

  @min_delay 2

  @doc """
  If the template is not defined for the message send text messages
  """
  @spec send_message(FlowContext.t(), Action.t(), [Message.t()]) :: {:ok, map(), any()}
  def send_message(context, %Action{templating: nil} = action, messages) do
    # get the test translation if needed
    text = Localization.get_translation(context, action)

    # Since we are saving the data after loading the flow
    # so we have to fetch the latest contact fields
    message_vars = %{
      "contact" => get_contact_field_map(context.contact_id)
    }

    body =
      text
      |> MessageVarParser.parse(message_vars)
      |> MessageVarParser.parse_results(context.results)

    organization_id = context.organization_id
    {type, media_id} = get_media_from_attachment(action.attachments, action.text, organization_id)

    attrs = %{
      uuid: action.uuid,
      body: body,
      type: type,
      media_id: media_id,
      receiver_id: context.contact_id,
      organization_id: organization_id,
      flow_id: context.flow_id,
      send_at: DateTime.add(DateTime.utc_now(), context.delay)
    }

    # we'll mark that we came here and are planning to send it, even if
    # we dont end up sending it. This allows us to detect and abort infinite loops
    context = FlowContext.update_recent(context, body, :recent_outbound)

    # count the number of times we sent the same message in the recent list
    # in the past 6 hours
    count = FlowContext.match_outbound(context, action.uuid)

    cond do
      count >= 7 ->
        # :loop_infinite, for now we just ignore this error, and stay put
        # we might want to reset the context
        # this typically will happen when there is no Exit pathway out of the loop
        {:ok, context, messages}

      count >= 5 ->
        # :loop_detected
        {:ok, context, [Messages.create_temp_message(organization_id, "Exit Loop") | messages]}

      true ->
        {:ok, _message} = Messages.create_and_send_message(attrs)
        # increment the delay
        {:ok, %{context | delay: context.delay + @min_delay}, messages}
    end
  end

  @doc """
  Given a shortcode and a context, send the right session template message
  to the contact
  """
  def send_message(
        context,
        %Action{templating: templating, attachments: attachments},
        messages
      ) do
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}
    vars = Enum.map(templating.variables, &MessageVarParser.parse(&1, message_vars))
    session_template = Messages.parse_template_vars(templating.template, vars)

    {type, media_id} = get_media_from_attachment(attachments, "", context.organization_id)

    session_template =
      session_template
      |> Map.merge(%{media_id: media_id, type: type})

    {:ok, _message} =
      Messages.create_and_send_session_template(
        session_template,
        %{
          receiver_id: context.contact_id,
          flow_id: context.flow_id,
          send_at: DateTime.add(DateTime.utc_now(), context.delay)
        }
      )

    # increment the delay
    {:ok, %{context | delay: context.delay + @min_delay}, messages}
  end

  @spec get_media_from_attachment(any(), any(), non_neg_integer()) :: any()
  defp get_media_from_attachment(attachment, _, _) when attachment == %{} or is_nil(attachment),
    do: {:text, nil}

  defp get_media_from_attachment(attachment, caption, organization_id) do
    [type | _tail] = Map.keys(attachment)

    url =
      attachment[type]
      |> String.trim()

    type = String.to_existing_atom(type)

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

  @spec get_contact_field_map(integer) :: map()
  defp get_contact_field_map(contact_id) do
    contact =
      Contacts.get_contact!(contact_id)
      |> Repo.preload(:language)
      |> Map.from_struct()

    put_in(contact, [:fields, :language], %{label: contact.language.label})
  end
end
