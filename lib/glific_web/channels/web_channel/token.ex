defmodule GlificWeb.WebChannel.Token do
  @moduledoc """
  Signs and verifies the JWT authenticating a browser contact on the web channel socket.

  Distinct from staff auth tokens — different signing key, different payload shape — so it can
  never authorize the staff-facing GraphQL API.

  A JWT rather than a `Phoenix.Token` because the same socket will also accept an NGO-minted JWT
  (`api-auth-design.md` §2), so `connect/3` verifies one shape rather than branching on two, and
  because §4.5's session-eviction rule needs the `jti` this supplies. §2.1 there describes the
  **NGO-minted** token, whose `kid` resolves a per-org key; this one has no `kid` — there is a
  single key Glific owns both ends of — which is why `org_id` is carried as a claim instead.
  """

  alias Glific.Contacts.Contact
  alias JOSE.{JWK, JWS, JWT}
  alias Plug.Crypto.KeyGenerator

  @algorithm "HS256"

  # Matches the claim the NGO-minted token carries, so one verifier can reject another channel's.
  @channel "web"

  # api-auth-design.md §2.4's cap. Was 24h until renewal existed, since a short TTL with no
  # refresh signs a beneficiary out mid-conversation.
  @ttl_seconds 3_600

  # Without an outer bound a short TTL buys nothing against a stolen token: the thief refreshes it
  # forever, and the only effect is more frequent renewals of their access.
  @session_max_seconds 86_400

  # The design's "clock leeway <= 60s".
  @leeway_seconds 60

  # Derived from secret_key_base rather than being it, so this token is not interchangeable with
  # anything else signed from that base.
  @key_salt "web_channel_contact_jwt"
  @key_length 32

  @type payload :: %{
          contact_id: non_neg_integer(),
          org_id: non_neg_integer(),
          session_id: String.t(),
          session_started_at: non_neg_integer()
        }

  @doc """
  Sign a token authorizing the given contact to connect to the web channel socket.
  """
  @spec sign_contact_token(Contact.t()) :: String.t()
  def sign_contact_token(%Contact{} = contact) do
    issued_at = System.system_time(:second)

    mint(
      to_string(contact.id),
      contact.organization_id,
      # Identifies the session, not the token. #5663's eviction rule compares this to decide
      # whether a connection is the same session reconnecting or a new login displacing it.
      Ecto.UUID.generate(),
      issued_at,
      issued_at
    )
  end

  @doc """
  Exchange a still-valid token for a fresh one.

  `jti` and `sst` carry over rather than being regenerated: a new `jti` would make every refresh
  look to #5663's eviction rule like a second login displacing the first, and a new `sst` would
  make renewal unbounded. An expired token is refused, or expiry would be advisory.
  """
  @spec renew_contact_token(String.t() | nil) ::
          {:ok, String.t(), payload()} | {:error, :expired | :invalid | :missing}
  def renew_contact_token(token) do
    with {:ok, payload} <- verify_contact_token(token) do
      now = System.system_time(:second)

      if now - payload.session_started_at >= @session_max_seconds do
        {:error, :expired}
      else
        renewed =
          mint(
            to_string(payload.contact_id),
            payload.org_id,
            payload.session_id,
            payload.session_started_at,
            now
          )

        {:ok, renewed, payload}
      end
    end
  end

  @spec mint(String.t(), non_neg_integer(), String.t(), non_neg_integer(), non_neg_integer()) ::
          String.t()
  defp mint(sub, org_id, jti, session_started_at, issued_at) do
    claims = %{
      "sub" => sub,
      "channel" => @channel,
      "org_id" => org_id,
      "jti" => jti,
      # Preserved across renewals; bounds total session life however often it is refreshed.
      "sst" => session_started_at,
      "iat" => issued_at,
      "exp" => issued_at + @ttl_seconds
    }

    {_jws, token} =
      signing_key()
      |> JWT.sign(%{"alg" => @algorithm}, claims)
      |> JWS.compact()

    token
  end

  @doc """
  Verify a web channel contact token, returning the contact and organization it authorizes.

  Every failure collapses to `:invalid` apart from an expired token and a missing one, so a caller
  cannot learn *why* a token was rejected.
  """
  @spec verify_contact_token(String.t() | nil) ::
          {:ok, payload()} | {:error, :expired | :invalid | :missing}
  def verify_contact_token(token) when is_binary(token) and token != "" do
    case JWT.verify_strict(signing_key(), [@algorithm], token) do
      {true, %JWT{fields: claims}, _jws} -> validate_claims(claims)
      _ -> {:error, :invalid}
    end
  rescue
    # A malformed token makes JOSE raise rather than return false.
    _ -> {:error, :invalid}
  end

  def verify_contact_token(_), do: {:error, :missing}

  @spec validate_claims(map()) :: {:ok, payload()} | {:error, :expired | :invalid}
  defp validate_claims(
         %{
           "sub" => sub,
           "channel" => @channel,
           "org_id" => org_id,
           "jti" => jti,
           "sst" => session_started_at,
           "iat" => iat,
           "exp" => exp
         } = _claims
       )
       when is_binary(sub) and is_integer(org_id) and is_binary(jti) and
              is_integer(session_started_at) and is_integer(iat) and is_integer(exp) do
    with :ok <- validate_timing(session_started_at, iat, exp) do
      to_payload(sub, org_id, jti, session_started_at)
    end
  end

  defp validate_claims(_claims), do: {:error, :invalid}

  @spec validate_timing(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :expired | :invalid}
  defp validate_timing(session_started_at, iat, exp) do
    now = System.system_time(:second)

    cond do
      # Forward-dating is rejected before expiry is considered, so a token cannot be given an
      # arbitrarily long life by claiming to have been issued in the future.
      iat > now + @leeway_seconds -> {:error, :invalid}
      session_started_at > now + @leeway_seconds -> {:error, :invalid}
      exp <= now - @leeway_seconds -> {:error, :expired}
      # A session past its absolute bound is refused on every read, not only on renewal, so an
      # over-age token cannot be spent on the socket either.
      now - session_started_at >= @session_max_seconds -> {:error, :expired}
      true -> :ok
    end
  end

  @spec to_payload(String.t(), non_neg_integer(), String.t(), non_neg_integer()) ::
          {:ok, payload()} | {:error, :invalid}
  defp to_payload(sub, org_id, jti, session_started_at) do
    case Integer.parse(sub) do
      {contact_id, ""} when contact_id > 0 ->
        {:ok,
         %{
           contact_id: contact_id,
           org_id: org_id,
           session_id: jti,
           session_started_at: session_started_at
         }}

      _ ->
        {:error, :invalid}
    end
  end

  @spec signing_key() :: JWK.t()
  defp signing_key do
    GlificWeb.Endpoint.config(:secret_key_base)
    |> KeyGenerator.generate(@key_salt, length: @key_length)
    |> JWK.from_oct()
  end
end
