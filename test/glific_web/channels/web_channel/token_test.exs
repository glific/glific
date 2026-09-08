defmodule GlificWeb.WebChannel.TokenTest do
  @moduledoc false
  use Glific.DataCase

  alias Glific.Fixtures
  alias GlificWeb.WebChannel.Token
  alias Plug.Crypto.KeyGenerator

  @algorithm "HS256"
  @key_salt "web_channel_contact_jwt"

  setup do
    %{contact: Fixtures.contact_fixture()}
  end

  # Mirrors the module's own key derivation so tests can mint hostile tokens that are correctly
  # signed but wrong in some other way — the only way to prove the claim checks rather than the
  # signature check is what rejects them.
  defp signing_key do
    GlificWeb.Endpoint.config(:secret_key_base)
    |> KeyGenerator.generate(@key_salt, length: 32)
    |> JOSE.JWK.from_oct()
  end

  defp sign(claims, jwk \\ nil, alg \\ @algorithm) do
    {_jws, token} =
      (jwk || signing_key())
      |> JOSE.JWT.sign(%{"alg" => alg}, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp valid_claims(contact, overrides \\ %{}) do
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

  describe "sign_contact_token/1 and verify_contact_token/1" do
    test "round-trips a contact", %{contact: contact} do
      token = Token.sign_contact_token(contact)

      assert {:ok, payload} = Token.verify_contact_token(token)
      assert payload.contact_id == contact.id
      assert payload.org_id == contact.organization_id
      assert is_binary(payload.session_id)
    end

    test "issues a distinct session id per sign, so two logins are distinguishable", %{
      contact: contact
    } do
      {:ok, first} = contact |> Token.sign_contact_token() |> Token.verify_contact_token()
      {:ok, second} = contact |> Token.sign_contact_token() |> Token.verify_contact_token()

      # #5663's eviction rule decides "same session reconnecting" vs "new login displacing the
      # previous one" by comparing these. Equal ids there would make eviction impossible.
      refute first.session_id == second.session_id
    end

    test "the token really is a JWT with the expected header and claims", %{contact: contact} do
      token = Token.sign_contact_token(contact)

      # Decoded off the wire rather than through JOSE.JWT.peek_protected/1, which lifts "alg"
      # into the JWS struct and out of `fields` — so asserting on `fields` would silently prove
      # nothing about the algorithm actually on the token.
      [header_segment, _payload, _signature] = String.split(token, ".")

      assert %{"alg" => @algorithm, "typ" => "JWT"} =
               header_segment |> Base.url_decode64!(padding: false) |> Jason.decode!()

      claims = JOSE.JWT.peek_payload(token).fields

      assert claims["sub"] == to_string(contact.id)
      assert claims["channel"] == "web"
      assert claims["org_id"] == contact.organization_id
      assert claims["exp"] - claims["iat"] == 3_600
      assert claims["sst"] == claims["iat"]
    end
  end

  describe "renew_contact_token/1" do
    test "returns a fresh token for the same session", %{contact: contact} do
      original = Token.sign_contact_token(contact)
      {:ok, before} = Token.verify_contact_token(original)

      assert {:ok, renewed, ^before} = Token.renew_contact_token(original)
      assert {:ok, after_renewal} = Token.verify_contact_token(renewed)

      assert after_renewal.contact_id == contact.id
      assert after_renewal.org_id == contact.organization_id

      # jti names the session, and #5663 evicts a socket when it sees a different one. A refresh
      # that minted a new jti would read as a second login displacing the first, so every
      # refresh would kick the user off their own socket.
      assert after_renewal.session_id == before.session_id

      # sst is what bounds renewal. Resetting it on each refresh would make the cap unreachable
      # and the session immortal.
      assert after_renewal.session_started_at == before.session_started_at
    end

    test "refuses an expired token rather than resurrecting it", %{contact: contact} do
      now = System.system_time(:second)

      expired =
        contact
        |> valid_claims(%{"sst" => now - 7_200, "iat" => now - 7_200, "exp" => now - 60})
        |> sign()

      assert {:error, :expired} = Token.renew_contact_token(expired)
    end

    test "refuses once the session passes its absolute bound", %{contact: contact} do
      now = System.system_time(:second)

      # Individually valid — issued a minute ago, expiring in an hour — but belonging to a session
      # that began 25 hours ago. Without the bound, a stolen token could be refreshed forever and
      # the one hour TTL would buy nothing.
      over_age =
        contact
        |> valid_claims(%{"sst" => now - 90_000, "iat" => now - 60, "exp" => now + 3_540})
        |> sign()

      assert {:error, :expired} = Token.renew_contact_token(over_age)
      # and it is refused on plain verification too, so it cannot be spent on the socket either
      assert {:error, :expired} = Token.verify_contact_token(over_age)
    end

    test "refuses a forged token", %{contact: contact} do
      foreign_key = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))

      assert {:error, :invalid} =
               contact |> valid_claims() |> sign(foreign_key) |> Token.renew_contact_token()
    end

    test "refuses a missing token" do
      assert {:error, :missing} = Token.renew_contact_token(nil)
      assert {:error, :missing} = Token.renew_contact_token("")
    end
  end

  describe "verify_contact_token/1 rejects" do
    test "a token signed with the wrong key", %{contact: contact} do
      foreign_key = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))

      assert {:error, :invalid} =
               contact |> valid_claims() |> sign(foreign_key) |> Token.verify_contact_token()
    end

    test "an alg:none token — the classic JWT forgery", %{contact: contact} do
      # Hand-built rather than signed, because JOSE will not mint an unsecured token without
      # being explicitly told to allow it. This is exactly what an attacker sends: real claims,
      # header rewritten to "none", signature dropped.
      header =
        %{"alg" => "none", "typ" => "JWT"} |> Jason.encode!() |> Base.url_encode64(padding: false)

      payload = contact |> valid_claims() |> Jason.encode!() |> Base.url_encode64(padding: false)
      forged = "#{header}.#{payload}."

      assert {:error, :invalid} = Token.verify_contact_token(forged)
    end

    test "a token signed with a different HMAC algorithm", %{contact: contact} do
      # HS512 against the *correct* key. The signature is genuine; only the algorithm differs.
      # verify_strict/3 rejects it because the permitted algorithm comes from our code, never
      # from the token's header.
      assert {:error, :invalid} =
               contact
               |> valid_claims()
               |> sign(signing_key(), "HS512")
               |> Token.verify_contact_token()
    end

    test "a tampered payload", %{contact: contact} do
      other = Fixtures.contact_fixture(%{phone: "919#{System.unique_integer([:positive])}"})
      [header, _payload, signature] = contact |> valid_claims() |> sign() |> String.split(".")

      swapped =
        contact
        |> valid_claims(%{"sub" => to_string(other.id)})
        |> Jason.encode!()
        |> Base.url_encode64(padding: false)

      assert {:error, :invalid} =
               Token.verify_contact_token("#{header}.#{swapped}.#{signature}")
    end

    test "an expired token", %{contact: contact} do
      now = System.system_time(:second)

      assert {:error, :expired} =
               contact
               |> valid_claims(%{
                 "sst" => now - 7_200,
                 "iat" => now - 7_200,
                 "exp" => now - 3_600
               })
               |> sign()
               |> Token.verify_contact_token()
    end

    test "a token issued in the future", %{contact: contact} do
      now = System.system_time(:second)

      # Without this check a forger with a valid key could mint an effectively immortal token by
      # dating it forward, since exp is only ever compared against the clock.
      assert {:error, :invalid} =
               contact
               |> valid_claims(%{
                 "sst" => now + 3_600,
                 "iat" => now + 3_600,
                 "exp" => now + 7_200
               })
               |> sign()
               |> Token.verify_contact_token()
    end

    test "a token for another channel", %{contact: contact} do
      assert {:error, :invalid} =
               contact
               |> valid_claims(%{"channel" => "whatsapp"})
               |> sign()
               |> Token.verify_contact_token()
    end

    test "a token missing a required claim", %{contact: contact} do
      for claim <- ["sub", "channel", "org_id", "jti", "sst", "iat", "exp"] do
        token = contact |> valid_claims() |> Map.delete(claim) |> sign()

        assert {:error, :invalid} = Token.verify_contact_token(token),
               "a token with no #{claim} claim was accepted"
      end
    end

    test "a non-numeric subject", %{contact: contact} do
      assert {:error, :invalid} =
               contact
               |> valid_claims(%{"sub" => "1; DROP TABLE contacts"})
               |> sign()
               |> Token.verify_contact_token()
    end

    test "garbage, an empty string and nil" do
      assert {:error, :invalid} = Token.verify_contact_token("not-a-token")
      assert {:error, :invalid} = Token.verify_contact_token("a.b.c")
      assert {:error, :missing} = Token.verify_contact_token("")
      assert {:error, :missing} = Token.verify_contact_token(nil)
    end
  end
end
