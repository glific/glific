defmodule Glific.Flows.ContactAction do
  @moduledoc """
  Since many of the functions, also do a few actions like send a message etc
  centralizing it here
  """

  alias Glific.{
    Contacts,
    Flows.Action,
    Flows.FlowContext,
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
  def send_message(context, %Action{templating: templating, text: text}) when is_nil(templating) do
    contact = Glific.Contacts.get_contact!(context.contact_id)

    contact_vars =
      contact.fields
      |> Enum.reduce(%{}, fn {field, map}, acc -> Map.put(acc, field, map["value"]) end)

    message_vars = %{"contact" => %{"fields" => contact_vars}}
    body = Glific.Flows.NaiveParser.parse(text, message_vars)
    Messages.create_and_send_message(%{body: body, type: :text, receiver_id: context.contact_id})
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


defmodule Glific.Flows.NaiveParser do
  @varname [".", "_" | Enum.map(?a..?z, &<<&1>>)]
  def parse(input, binding) do
    do_parse(input, binding, {nil, ""})
  end

  defp do_parse("", binding, {var, result}) do
    result <> bound(var, binding)
  end

  defp do_parse("@" <> rest, binding, {nil, result}) do
    do_parse(rest, binding, {"", result})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, binding, {nil, result}) do
    do_parse(rest, binding, {nil, result <> c})
  end


  defp do_parse(<<c::binary-size(1), rest::binary>>, binding, {var, result}) when c in @varname do
    do_parse(rest, binding, {var <> c, result})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, binding, {var, result}) do
    do_parse(rest, binding, {nil, result <> bound(var, binding) <> c})
  end


  defp bound(nil, _binding), do: ""

  defp bound(var, binding) do
    substitution = get_in(binding, String.split(var, "."))
    IO.inspect("var")
    IO.inspect(var)

    IO.inspect("binding")
    IO.inspect(binding)

    if substitution == nil, do: "@#{var}", else: substitution
  end
end
