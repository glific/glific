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
    Repo
  }

  @min_delay 2

  @doc """
  If the template is not define for the message send text messages
  """
  @spec send_message(FlowContext.t(), Action.t(), [String.t()])
  :: {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def send_message(context, %Action{templating: nil, text: _text} = action, message_stream) do
    # get the test translation if needed
    text = Localization.get_translation(context, action)

    # Since we are saving the data after loading the flow
    # so we have to fetch the latest contact fields
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}
    body = MessageVarParser.parse(text, message_vars)

    {type, media_id} = get_media_from_attachment(action.attachments, action.text)

    result =
      Messages.create_and_send_message(%{
        uuid: action.uuid,
        body: body,
        type: type,
        media_id: media_id,
        receiver_id: context.contact_id,
        send_at: DateTime.add(DateTime.utc_now(), context.delay)
      })

    case result do
      # increment the delay
      {:ok, _message} ->
        {:ok, %{context | delay: context.delay + @min_delay}, message_stream}

      # we need to do something here to progress the flow
      # maybe set something in the context for the downstream node to detect and move on
      {:error, :loop_detected} ->
        {:ok, %{context | delay: context.delay + @min_delay}, ["Exit" | message_stream]}

      _ -> {:error, "Could not send message. Aborting for now"}
    end
  end

  @doc """
  Given a shortcode and a context, send the right session template message
  to the contact
  """
  def send_message(context, %Action{templating: templating, attachments: attachments}, message_stream) do
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}
    vars = Enum.map(templating.variables, &MessageVarParser.parse(&1, message_vars))
    session_template = Messages.parse_template_vars(templating.template, vars)

    {type, media_id} = get_media_from_attachment(attachments, "")

    session_template =
      session_template
      |> Map.merge(%{media_id: media_id, type: type})

    {:ok, _message} =
      Messages.create_and_send_session_template(
        session_template,
        %{
          receiver_id: context.contact_id,
          send_at: DateTime.add(DateTime.utc_now(), context.delay)
        }
      )

    # increment the delay
    {:ok, %{context | delay: context.delay + @min_delay}, message_stream}
  end

  @spec get_media_from_attachment(map(), any()) :: {atom(), nil | integer()}
  defp get_media_from_attachment(attachment, _) when attachment == %{} or is_nil(attachment),
    do: {:text, nil}

  defp get_media_from_attachment(attachment, caption) do
    [type | _tail] = Map.keys(attachment)
    url = attachment[type]

    type = String.to_existing_atom(type)

    {:ok, message_media} =
      %{
        type: type,
        url: url,
        source_url: url,
        thumbnail: url,
        caption: caption
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
    Contacts.contact_opted_out(context.contact.phone, DateTime.utc_now())
    context
  end

  @spec get_contact_field_map(integer) :: map()
  defp get_contact_field_map(contact_id) do
    contact =
      Contacts.get_contact!(contact_id)
      |> Repo.preload([:language])
      |> Map.from_struct()

    put_in(contact, [:fields, :language], %{label: contact.language.label})
  end
end
