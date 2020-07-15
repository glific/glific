defmodule Glific.Flows.ContactAction do
  @moduledoc """
  Since many of the functions, also do a few actions like send a message etc
  centralizing it here
  """

  alias Glific.{
    Contacts,
    Flows.FlowContext,
    Flows.Action,
    Messages,
    Processor.Helper
  }

  defp send_session_message_template(context, shortcode) do
    language_id = context.contact.language_id

    session_template = Helper.get_session_message_template(shortcode, language_id)

    {:ok, _message} =
      Messages.create_and_send_session_template(session_template, context.contact_id)
  end

  @doc """
  If the template is not define for the message send text messages
  """
  @spec send_message(FlowContext.t(), Action.t()) :: FlowContext.t()
  def send_message(context, %Action{templating: templating, text: text})
      when is_nil(templating) do
    Messages.create_and_send_message(%{body: text, type: :text, receiver_id: context.contact_id})
    context
  end

  @doc """
  Given a shortcode and a context, send the right session template message
  to the contact
  """
  def send_message(context, %Action{templating: templating}) do
    send_session_message_template(context, templating.template.shortcode)
    context
  end

  @doc """
  Contact opts out
  """
  @spec optout(FlowContext.t()) :: FlowContext.t()
  def optout(context) do
    send_session_message_template(context, "optout")

    # We need to update the contact with optout_time and status
    Contacts.contact_opted_out(context.contact.phone, DateTime.utc_now())
    context
  end
end
