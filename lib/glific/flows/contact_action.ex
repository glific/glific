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
  def send_message(context, %Action{templating: templating, text: _text} = action)
      when is_nil(templating) do
    # get the test translation if needed
    text = Localization.get_translation(context, action)

    # Since we are saving the data after loading the flow
    # so we have to fetch the latest contact fields
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}
    body = MessageVarParser.parse(text, message_vars)
    # super hack for now, lets wait for the previous messages to go out
    :timer.sleep(50)

    {:ok, _message} =
      Messages.create_and_send_message(%{body: body, type: :text, receiver_id: context.contact_id})

    context
  end

  @doc """
  Given a shortcode and a context, send the right session template message
  to the contact
  """
  def send_message(context, %Action{templating: templating}) do
    message_vars = %{"contact" => get_contact_field_map(context.contact_id)}

    vars = Enum.map(templating.variables, &MessageVarParser.parse(&1, message_vars))
    session_template = Messages.parse_template_vars(templating.template, vars)

    # super hack for now, lets wait for the previous messages to go out
    :timer.sleep(50)

    {:ok, _message} =
      Messages.create_and_send_session_template(session_template, context.contact_id)

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

  @spec get_contact_field_map(integer) :: map()
  defp get_contact_field_map(contact_id) do
    contact =
      Glific.Contacts.get_contact!(contact_id)
      |> Glific.Repo.preload([:language])

    contact.fields
    |> Enum.reduce(%{"fields" => %{}}, fn {field, map}, acc ->
      put_in(acc, ["fields", field], map["value"])
    end)
    |> put_in(["fields", :language], %{label: contact.language.label})
  end
end
