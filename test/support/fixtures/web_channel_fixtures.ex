defmodule Glific.WebChannelFixtures do
  @moduledoc """
  Test helpers for an authenticated web channel socket, so a channel test doesn't have to
  repeat the JWT mint/connect/join dance in every file.

  Mints a real token via `GlificWeb.WebChannel.Token.generate/2` rather than stubbing
  `verify/3` — the whole point of the socket is that it rejects bad credentials, and a stubbed
  verifier would test nothing about it.
  """

  import Phoenix.ChannelTest

  alias Glific.{Contacts, Fixtures}
  alias Glific.Contacts.Contact
  alias Glific.WebChannelFlagHelpers
  alias GlificWeb.WebChannel.{RoomChannel, Token}
  alias GlificWeb.WebChannelSocket
  alias JOSE.{JWK, JWS, JWT}

  @endpoint GlificWeb.Endpoint

  @doc """
  A contact with a normalized, digits-only phone, the shape OTP login stores as the web identity.
  """
  @spec web_contact_fixture(map()) :: Contact.t()
  def web_contact_fixture(attrs \\ %{}) do
    phone = "91" <> to_string(7_000_000_000 + System.unique_integer([:positive]))
    Fixtures.contact_fixture(Map.put_new(attrs, :phone, phone))
  end

  @doc """
  A Glific session token for `contact`, as the OTP login mints it: its `sub` is the contact's phone,
  which is also its web identity. Needs the organization to have a secret, as the channel being
  enabled gives it.
  """
  @spec web_channel_session_token(Contact.t()) :: String.t()
  def web_channel_session_token(%Contact{} = contact) do
    {:ok, _contact} = Contacts.add_identity(contact, :web, contact.phone)
    {:ok, token} = Token.generate(contact.organization_id, contact.phone)
    token
  end

  @doc """
  Mints a session token for `contact` (or uses `opts[:token]`, so forgery/expiry cases can be
  tested through the same connect door) and returns a connected `WebChannelSocket`.
  """
  @spec web_channel_socket_fixture(Contact.t(), keyword()) :: {:ok, Phoenix.Socket.t()} | :error
  def web_channel_socket_fixture(%Contact{} = contact, opts \\ []) do
    token = Keyword.get_lazy(opts, :token, fn -> web_channel_session_token(contact) end)
    connect_with_token(token, opts)
  end

  @doc """
  Connects a `WebChannelSocket` with `token` the way a browser does, the organization coming from
  `opts[:host]` (the default organization's host when omitted) and any `opts[:connect_info]`.
  """
  @spec connect_with_token(String.t(), keyword()) :: {:ok, Phoenix.Socket.t()} | :error
  def connect_with_token(token, opts \\ []) do
    host = Keyword.get(opts, :host, "localhost")

    connect_info =
      opts |> Keyword.get(:connect_info, %{}) |> Map.put(:uri, %URI{scheme: "wss", host: host})

    connect(WebChannelSocket, %{"token" => token}, connect_info: connect_info)
  end

  @doc """
  Joins `web_channel:conversation` on `socket`.
  """
  @spec join_web_channel(Phoenix.Socket.t()) ::
          {:ok, map(), Phoenix.Socket.t()} | {:error, map()}
  def join_web_channel(socket),
    do: subscribe_and_join(socket, RoomChannel, "web_channel:conversation")

  @doc """
  Default valid session claims for `contact`, letting a test override just the field it cares
  about (an already-past `"exp"`, an old `"sst"`, etc.) — the sweep and expiry tests need claim
  shapes `Token.generate/2` has no way to express.
  """
  @spec web_channel_claims(Contact.t(), map()) :: map()
  def web_channel_claims(%Contact{} = contact, overrides \\ %{}) do
    {:ok, _contact} = Contacts.add_identity(contact, :web, contact.phone)
    now = System.system_time(:second)

    Map.merge(
      %{
        "sub" => contact.phone,
        "channel" => "web",
        "jti" => Ecto.UUID.generate(),
        "sst" => now,
        "iat" => now,
        "exp" => now + 3_600
      },
      overrides
    )
  end

  @doc """
  Signs a raw claims map with `secret`, by default the default organization's own, so a test can
  mint a token carrying a claim shape the real signing helpers don't expose.
  """
  @spec sign_web_channel_claims(map(), String.t() | nil) :: String.t()
  def sign_web_channel_claims(claims, secret \\ nil) do
    {_jws, token} =
      (secret || WebChannelFlagHelpers.web_channel_secret())
      |> JWK.from_oct()
      |> JWT.sign(%{"alg" => "HS256"}, claims)
      |> JWS.compact()

    token
  end
end
