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

  # 24 hours, carried over from the Phoenix.Token this replaces. api-auth-design.md §2.4 caps the
  # NGO-minted token at one hour, but that cap is only survivable alongside the `token_expiring` /
  # `renew_token` handshake described in the same section, which does not exist yet — shortening
  # this before that ships would sign a beneficiary out mid-conversation with no way back.
  @ttl_seconds 86_400

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
          session_id: String.t()
        }

  @doc """
  Sign a token authorizing the given contact to connect to the web channel socket.
  """
  @spec sign_contact_token(Contact.t()) :: String.t()
  def sign_contact_token(%Contact{} = contact) do
    issued_at = System.system_time(:second)

    claims = %{
      "sub" => to_string(contact.id),
      "channel" => @channel,
      "org_id" => contact.organization_id,
      # Identifies the session, not the token. #5663's eviction rule compares this to decide
      # whether a connection is the same session reconnecting or a new login displacing it.
      "jti" => Ecto.UUID.generate(),
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
           "iat" => iat,
           "exp" => exp
         } = _claims
       )
       when is_binary(sub) and is_integer(org_id) and is_binary(jti) and
              is_integer(iat) and is_integer(exp) do
    now = System.system_time(:second)

    cond do
      # Rejected before the expiry check so a token claiming to be from the future cannot be
      # used to manufacture an arbitrarily long lifetime.
      iat > now + @leeway_seconds -> {:error, :invalid}
      exp <= now - @leeway_seconds -> {:error, :expired}
      true -> to_payload(sub, org_id, jti)
    end
  end

  defp validate_claims(_claims), do: {:error, :invalid}

  @spec to_payload(String.t(), non_neg_integer(), String.t()) ::
          {:ok, payload()} | {:error, :invalid}
  defp to_payload(sub, org_id, jti) do
    case Integer.parse(sub) do
      {contact_id, ""} when contact_id > 0 ->
        {:ok, %{contact_id: contact_id, org_id: org_id, session_id: jti}}

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
