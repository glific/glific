defmodule Glific.WebChannelFixtures do
  @moduledoc """
  Test helpers for an authenticated web channel socket, so a channel test doesn't have to
  repeat the JWT mint/connect/join dance in every file.

  Mints a real token via `GlificWeb.WebChannel.Token.sign_contact_token/1` rather than stubbing
  `verify_contact_token/1` — the whole point of the socket is that it rejects bad credentials,
  and a stubbed verifier would test nothing about it.
  """

  import Phoenix.ChannelTest

  alias Glific.Contacts.Contact
  alias GlificWeb.WebChannel.{RoomChannel, Token}
  alias GlificWeb.WebChannelSocket
  alias JOSE.{JWK, JWS, JWT}
  alias Plug.Crypto.KeyGenerator

  @endpoint GlificWeb.Endpoint

  # Matches GlificWeb.WebChannel.Token's own salt, so `sign_web_channel_claims/2` produces a
  # token that verifies through the real signing path.
  @key_salt "web_channel_contact_jwt"

  @doc """
  Mints a token for `contact` (or uses `opts[:token]`, so forgery/expiry cases can be tested
  through the same connect door) and returns a connected `WebChannelSocket`.
  """
  @spec web_channel_socket_fixture(Contact.t(), keyword()) :: {:ok, Phoenix.Socket.t()} | :error
  def web_channel_socket_fixture(%Contact{} = contact, opts \\ []) do
    token = Keyword.get(opts, :token, Token.sign_contact_token(contact))
    connect(WebChannelSocket, %{"token" => token})
  end

  @doc """
  Joins `web_channel:<contact.id>` on `socket`.
  """
  @spec join_web_channel(Phoenix.Socket.t(), Contact.t()) ::
          {:ok, map(), Phoenix.Socket.t()} | {:error, map()}
  def join_web_channel(socket, %Contact{} = contact),
    do: subscribe_and_join(socket, RoomChannel, "web_channel:#{contact.id}")

  @doc """
  Default valid web channel JWT claims for `contact`, letting a test override just the field it
  cares about (an already-past `"exp"`, a foreign `"org_id"`, etc.) — the sweep and expiry tests
  need claim shapes `Token.sign_contact_token/1` has no way to express.
  """
  @spec web_channel_claims(Contact.t(), map()) :: map()
  def web_channel_claims(%Contact{} = contact, overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "sub" => to_string(contact.id),
        "channel" => "web",
        "org_id" => contact.organization_id,
        "jti" => Ecto.UUID.generate(),
        "sst" => now,
        "iat" => now,
        "exp" => now + 3_600
      },
      overrides
    )
  end

  @doc """
  Signs a raw claims map through the web channel's own key (or `jwk`, for forgery cases), so a
  test can mint a token carrying a claim shape the real signing helpers don't expose.
  """
  @spec sign_web_channel_claims(map(), JWK.t() | nil) :: String.t()
  def sign_web_channel_claims(claims, jwk \\ nil) do
    {_jws, token} =
      (jwk || signing_key())
      |> JWT.sign(%{"alg" => "HS256"}, claims)
      |> JWS.compact()

    token
  end

  @spec signing_key() :: JWK.t()
  defp signing_key do
    GlificWeb.Endpoint.config(:secret_key_base)
    |> KeyGenerator.generate(@key_salt, length: 32)
    |> JWK.from_oct()
  end
end
