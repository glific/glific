defmodule GlificWeb.WebChannel.Token do
  @moduledoc """
  Signs and verifies the JWT that authenticates a browser contact on the web channel socket
  (`GlificWeb.WebChannelSocket`).

  This token is intentionally distinct from staff auth tokens — different signing key, different
  payload shape (`sub`/`org_id` rather than a `user`) — so it can never be used to authorize the
  staff-facing GraphQL API.

  ## Why a JWT rather than a `Phoenix.Token`

  A `Phoenix.Token` would be sufficient for Glific's own widget on its own. The web channel is
  going to carry a second credential type, though: `api-auth-design.md` §2 has a partner NGO's
  backend minting its own HS256 JWT that the browser presents directly to this socket. Issuing a
  JWT here too means `connect/3` verifies one token *shape* rather than branching on two, and it
  gives the OTP path a real `jti` — which is what §4.5's session-eviction rule needs when it says
  the session identifier is "our UUID for OTP logins and the org's `jti` for JWTs".

  Note that the JWT contract in §2.1 of that document describes the **NGO-minted** token, whose
  `kid` resolves to a per-organization signing key. This module mints the **Glific-issued** token
  for the OTP flow: there is no `kid`, because there is exactly one key and Glific owns both ends
  of it, and `org_id` is a claim precisely because there is no `kid` to resolve the organization
  from.

  ## Verification

  `verify_strict/3` is used deliberately. Plain `JOSE.JWT.verify/2` selects the algorithm from the
  token's *own* header, which is the `alg: none` and HS/RS confusion vulnerability — an attacker
  re-signs with `{"alg":"none"}` and an empty signature, or with HMAC against a public key, and the
  library obligingly agrees. The permitted algorithm is passed in from here instead, so the token
  never gets a say in how it is checked.
  """

  alias Glific.Contacts.Contact
  alias JOSE.{JWK, JWS, JWT}
  alias Plug.Crypto.KeyGenerator

  # Pinned on both sign and verify. Never read from the token header.
  @algorithm "HS256"

  # Namespaces `sub`, matching the `channel` claim the NGO-minted token must also carry, so one
  # verifier can eventually reject a token minted for some other channel.
  @channel "web"

  # One hour, the cap api-auth-design.md §2.4 sets. This was 24 hours until renewal existed,
  # because a short TTL with no way to refresh signs a beneficiary out mid-conversation.
  @ttl_seconds 3_600

  # The outer bound on a session, regardless of how many times it is renewed. Without it a short
  # TTL buys nothing against a stolen token: the thief simply refreshes it forever, and the only
  # thing a one hour expiry would have achieved is more frequent renewals of the attacker's
  # access. Twenty-four hours keeps the worst case no worse than the fixed TTL this replaced.
  @session_max_seconds 86_400

  # Tolerance for clock skew between nodes, matching the design's "clock leeway <= 60s".
  @leeway_seconds 60

  # The signing key is derived from secret_key_base rather than being the secret itself, so this
  # token cannot be confused with anything else signed from that base, and rotating the base
  # rotates this key with it.
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
  Exchange a still-valid token for a fresh one, so a one hour TTL does not end a conversation.

  The session identity is deliberately carried over rather than regenerated. `jti` names the
  *session*, and #5663 evicts a socket when it sees a different one — minting a new `jti` here
  would make every refresh look like a second login displacing the first. `sst` carries over for
  the opposite reason: it is what stops renewal being unbounded.

  An expired token cannot be renewed. Resurrection would make expiry advisory.
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
      # When this session began, preserved across renewals. Bounds the total life of a session
      # independently of how often it is refreshed.
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
