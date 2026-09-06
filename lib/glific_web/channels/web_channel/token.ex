defmodule GlificWeb.WebChannel.Token do
  @moduledoc """
  Signs and verifies the short-lived token that authenticates a browser contact on the
  web channel socket (`GlificWeb.WebChannelSocket`).

  This token is intentionally distinct from staff auth tokens (different salt, different
  payload shape: `contact_id`/`org_id` instead of a `user`), so it can never be used to
  authorize the staff-facing GraphQL API.
  """

  alias Glific.Contacts.Contact

  @salt "web_channel_contact"
  @max_age 86_400

  @doc """
  Sign a token authorizing the given contact to connect to the web channel socket.
  """
  @spec sign_contact_token(Contact.t()) :: String.t()
  def sign_contact_token(%Contact{} = contact) do
    Phoenix.Token.sign(GlificWeb.Endpoint, @salt, %{
      contact_id: contact.id,
      org_id: contact.organization_id
    })
  end

  @doc """
  Verify a web channel contact token, returning the `contact_id`/`org_id` payload.
  """
  @spec verify_contact_token(String.t()) ::
          {:ok, %{contact_id: non_neg_integer(), org_id: non_neg_integer()}}
          | {:error, :expired | :invalid | :missing}
  def verify_contact_token(token) do
    Phoenix.Token.verify(GlificWeb.Endpoint, @salt, token, max_age: @max_age)
  end
end
