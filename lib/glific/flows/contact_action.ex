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
    Messages
  }

  @min_delay 2

  @doc """
  If the template is not define for the message send text messages
  """
  @spec send_message(FlowContext.t(), Action.t()) :: FlowContext.t()
  def send_message(context, %Action{templating: templating, text: _text} = action)
      when is_nil(templating) do
    # get the test translation if needed
    text = Localization.get_translation(context, action)

    # Since we are saving the data after loading the flow
    # so we have to fetch the latest contact fields
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}
    body = MessageVarParser.parse(text, message_vars)

   {type, media_id} = get_media_from_attachment(action.attachments)
    {:ok, _message} =
      Messages.create_and_send_message(%{
        body: body,
        type: :text,
        receiver_id: context.contact_id,
        send_at: DateTime.add(DateTime.utc_now(), context.delay)
      })

    # increment the delay
    %{context | delay: context.delay + @min_delay}
  end

  @doc """
  Given a shortcode and a context, send the right session template message
  to the contact
  """
  def send_message(context, %Action{templating: templating, attachments: attachments}) do
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}
    vars = Enum.map(templating.variables, &MessageVarParser.parse(&1, message_vars))
    session_template = Messages.parse_template_vars(templating.template, vars)

    {type, media_id} = get_media_from_attachment(attachments)

    {:ok, _message} =
      Messages.create_and_send_session_template(
        session_template,
        %{
          receiver_id: context.contact_id,
          send_at: DateTime.add(DateTime.utc_now(), context.delay)
        }
      )

    # increment the delay
    %{context | delay: context.delay + @min_delay}
  end


  @spec get_media_from_attachment(map()) :: {atom(), nil | integer()}
  defp get_media_from_attachment(%{}), do: {:text, nil}

  defp get_media_from_attachment(attachment) do
    IO.inspect(attachment)
    {:text, nil}
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
    contact = Contacts.get!(contact_id)
    |> put_in(["fields", :language], %{label: contact.language.label})
  end


end
