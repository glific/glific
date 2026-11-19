defmodule GlificWeb.WebChannel.DisplayName do
  @moduledoc """
  Resolves the display name shown for a web-channel contact.

  A contact carries two independent name stores: the top-level `contact.name` column (set by the
  WhatsApp push-name and the widget rename) and `contact.fields["name"]["value"]` (the JSONB field
  a flow writes and reads via `@contact.fields.name`). We prefer the flow-owned field so a name a
  flow captured shows up, falling back to `contact.name`, and finally `nil` (the widget then
  renders "You"). Shared by the OTP login response and the live socket update so both agree.
  """

  alias Glific.Contacts.Contact

  @doc """
  Return the best display name for `contact`: `fields.name` if present and non-blank, else
  `contact.name`, else `nil`. Expects `contact.fields` to be string-keyed (as read from the DB).
  """
  @spec resolve(Contact.t()) :: String.t() | nil
  def resolve(%Contact{fields: %{"name" => %{"value" => value}}})
      when is_binary(value) and value != "",
      do: value

  def resolve(%Contact{name: name}), do: name
end
