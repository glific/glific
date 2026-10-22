defmodule GlificWeb.WebChannel.TokenTest do
  # Not async: it flips the global `web_channel_enabled` and writes the organization's credential.
  use Glific.DataCase

  alias Glific.{WebChannelFlagHelpers, WebChannelLoginHelpers}
  alias GlificWeb.WebChannel.Token
  alias Plug.Crypto.KeyGenerator

  @secret "first-secret-first-secret-0123456"
  @now 1_800_000_000

  setup %{organization_id: organization_id} do
    activate_secrets(organization_id, [@secret])
    :ok
  end

  defp activate_secrets(organization_id, secrets),
    do:
      WebChannelFlagHelpers.activate_web_channel(
        organization_id,
        %{},
        WebChannelFlagHelpers.jwt_signature_secrets(secrets)
      )

  defp verify(organization_id, overrides, secret \\ @secret) do
    token =
      overrides |> WebChannelLoginHelpers.claims(@now) |> WebChannelLoginHelpers.sign(secret)

    Token.verify(organization_id, token, @now)
  end

  test "accepts a valid token", %{organization_id: organization_id} do
    assert {:ok, %{sub: "ravi_12", exp: exp} = claims} = verify(organization_id, %{})
    assert exp == @now + 600
    assert Enum.sort(Map.keys(claims)) == [:exp, :sub]
  end

  test "a secret of 31 characters never verifies, one of 32 does", %{
    organization_id: organization_id
  } do
    short = String.duplicate("s", 31)
    long = String.duplicate("s", 32)

    activate_secrets(organization_id, [short])
    assert {:error, :invalid} = verify(organization_id, %{}, short)

    activate_secrets(organization_id, [long])

    assert {:ok, %{sub: "ravi_12"}} = verify(organization_id, %{}, long)
  end

  test "rejects a token signed with any other secret", %{organization_id: organization_id} do
    assert {:error, :invalid} =
             verify(organization_id, %{}, "some-other-secret-some-other-secret")
  end

  test "rejects every token when the organization has no secret", %{
    organization_id: organization_id
  } do
    WebChannelFlagHelpers.remove_web_channel_secret(organization_id)

    assert {:error, :invalid} = verify(organization_id, %{})
  end

  test "never trusts the token's algorithm", %{organization_id: organization_id} do
    claims = WebChannelLoginHelpers.claims(%{}, @now)

    assert {:error, :invalid} =
             Token.verify(
               organization_id,
               WebChannelLoginHelpers.sign(claims, @secret, "HS512"),
               @now
             )

    unsigned = Base.url_encode64(~s({"alg":"none"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)

    assert {:error, :invalid} =
             Token.verify(organization_id, "#{unsigned}.#{payload}.", @now)
  end

  test "rejects a token that is not a JWT", %{organization_id: organization_id} do
    assert {:error, :invalid} = Token.verify(organization_id, "not-a-token", @now)
    assert {:error, :invalid} = Token.verify(organization_id, "", @now)
    assert {:error, :invalid} = Token.verify(organization_id, nil, @now)
  end

  test "rejects an organization that does not exist" do
    token = %{} |> WebChannelLoginHelpers.claims(@now) |> WebChannelLoginHelpers.sign(@secret)

    assert {:error, :invalid} = Token.verify(0, token, @now)
  end

  describe "required claims" do
    test "sub must be a string of 1 to 255 characters", %{organization_id: organization_id} do
      for sub <- [nil, "", 12, String.duplicate("a", 256)] do
        assert {:error, :invalid} = verify(organization_id, %{"sub" => sub}),
               "sub #{inspect(sub)}"
      end

      assert {:ok, _} = verify(organization_id, %{"sub" => String.duplicate("a", 255)})
    end

    test "channel must be web", %{organization_id: organization_id} do
      assert {:error, :invalid} = verify(organization_id, %{"channel" => "whatsapp"})
      assert {:error, :invalid} = verify(organization_id, %{"channel" => nil})
    end

    test "iat and exp must be integers", %{organization_id: organization_id} do
      for claim <- ["iat", "exp"], value <- [nil, "1800000000", 1_800_000_000.5] do
        assert {:error, :invalid} = verify(organization_id, %{claim => value}),
               "#{claim} #{inspect(value)}"
      end
    end
  end

  describe "timing" do
    test "the lifetime may be 24 hours and no more", %{organization_id: organization_id} do
      assert {:ok, _} = verify(organization_id, %{"exp" => @now + 86_400})
      assert {:error, :invalid} = verify(organization_id, %{"exp" => @now + 86_401})
    end

    test "an expired token is rejected beyond the leeway", %{organization_id: organization_id} do
      assert {:ok, _} =
               verify(organization_id, %{"iat" => @now - 120, "exp" => @now - 59})

      assert {:error, :invalid} =
               verify(organization_id, %{"iat" => @now - 120, "exp" => @now - 60})
    end

    test "an iat in the future is accepted only within the leeway", %{
      organization_id: organization_id
    } do
      assert {:ok, _} = verify(organization_id, %{"iat" => @now + 60, "exp" => @now + 600})

      assert {:error, :invalid} =
               verify(organization_id, %{"iat" => @now + 61, "exp" => @now + 600})
    end
  end

  describe "optional claims" do
    test "name and phone are returned", %{organization_id: organization_id} do
      assert {:ok, claims} =
               verify(organization_id, %{
                 "name" => "Ravi",
                 "phone" => "+91 98765 43210"
               })

      assert %{
               sub: "ravi_12",
               exp: @now + 600,
               name: "Ravi",
               phone: "919876543210"
             } ==
               claims
    end

    test "an invalid phone is treated as absent", %{organization_id: organization_id} do
      assert {:ok, claims} = verify(organization_id, %{"phone" => "12"})
      refute Map.has_key?(claims, :phone)
    end

    test "a name over 255 characters is rejected", %{organization_id: organization_id} do
      assert {:error, :invalid} = verify(organization_id, %{"name" => String.duplicate("a", 256)})
    end
  end

  test "reads the secret of the organization the request is for", %{
    organization_id: organization_id
  } do
    other_organization = Glific.Fixtures.organization_fixture()
    Repo.put_organization_id(organization_id)

    assert {:error, :invalid} = verify(other_organization.id, %{})
  end

  describe "session claims" do
    test "jti and sst come back as the session", %{organization_id: organization_id} do
      assert {:ok, claims} =
               verify(organization_id, %{"jti" => "session-1", "sst" => @now - 60})

      assert %{session_id: "session-1", session_started_at: started_at} = claims
      assert started_at == @now - 60
    end

    test "one of jti and sst without the other is rejected", %{organization_id: organization_id} do
      assert {:error, :invalid} = verify(organization_id, %{"jti" => "session-1"})
      assert {:error, :invalid} = verify(organization_id, %{"sst" => @now})
    end

    test "a session older than 24 hours is rejected, however fresh the token", %{
      organization_id: organization_id
    } do
      assert {:ok, _} = verify(organization_id, %{"jti" => "s", "sst" => @now - 86_399})
      assert {:error, :invalid} = verify(organization_id, %{"jti" => "s", "sst" => @now - 86_400})
    end

    test "a session started in the future is rejected beyond the leeway", %{
      organization_id: organization_id
    } do
      assert {:ok, _} = verify(organization_id, %{"jti" => "s", "sst" => @now + 60})
      assert {:error, :invalid} = verify(organization_id, %{"jti" => "s", "sst" => @now + 61})
    end
  end

  describe "sign/2" do
    test "round-trips with the organization's secret", %{organization_id: organization_id} do
      assert {:ok, token} = Token.sign(organization_id, %{sub: "ravi_12", name: "Ravi"})

      assert {:ok, %{sub: "ravi_12", name: "Ravi", exp: exp}} =
               Token.verify(organization_id, token)

      assert_in_delta exp, System.system_time(:second) + 3_600, 5
    end

    test "fails without a secret", %{organization_id: organization_id} do
      WebChannelFlagHelpers.remove_web_channel_secret(organization_id)

      assert {:error, :no_secret} = Token.sign(organization_id, %{sub: "ravi_12"})
    end
  end

  describe "generate/2 and renew/3" do
    test "a session token carries sub, jti and sst", %{organization_id: organization_id} do
      assert {:ok, token} = Token.generate(organization_id, "919876543210")

      assert {:ok, %{sub: "919876543210", session_id: session_id, session_started_at: started_at}} =
               Token.verify(organization_id, token)

      assert is_binary(session_id)
      assert_in_delta started_at, System.system_time(:second), 5
    end

    test "two sessions get distinct ids", %{organization_id: organization_id} do
      {:ok, first} = Token.generate(organization_id, "919876543210")
      {:ok, second} = Token.generate(organization_id, "919876543210")

      assert {:ok, %{session_id: first_id}} = Token.verify(organization_id, first)
      assert {:ok, %{session_id: second_id}} = Token.verify(organization_id, second)
      assert first_id != second_id
    end

    test "renewal keeps jti and sst and moves exp one hour out", %{
      organization_id: organization_id
    } do
      token =
        %{"sub" => "919876543210", "jti" => "s1", "sst" => @now - 1_000}
        |> WebChannelLoginHelpers.claims(@now - 500)
        |> WebChannelLoginHelpers.sign(@secret)

      assert {:ok, renewed, %{session_id: "s1"}} = Token.renew(organization_id, token, @now)

      assert {:ok, claims} = Token.verify(organization_id, renewed, @now)
      assert %{sub: "919876543210", session_id: "s1", exp: exp} = claims
      assert claims.session_started_at == @now - 1_000
      assert exp == @now + 3_600
    end

    test "renewal is refused once the session is 24 hours old", %{
      organization_id: organization_id
    } do
      token =
        %{"jti" => "s1", "sst" => @now - 86_400}
        |> WebChannelLoginHelpers.claims(@now)
        |> WebChannelLoginHelpers.sign(@secret)

      assert {:error, :invalid} = Token.renew(organization_id, token, @now)
    end

    test "renewal is refused for a token without a session", %{organization_id: organization_id} do
      token = %{} |> WebChannelLoginHelpers.claims(@now) |> WebChannelLoginHelpers.sign(@secret)

      assert {:error, :invalid} = Token.renew(organization_id, token, @now)
    end

    test "renewal is refused for an expired token and for nil", %{
      organization_id: organization_id
    } do
      expired =
        %{"jti" => "s1", "sst" => @now - 7_200, "iat" => @now - 7_200, "exp" => @now - 3_600}
        |> WebChannelLoginHelpers.claims(@now)
        |> WebChannelLoginHelpers.sign(@secret)

      assert {:error, :invalid} = Token.renew(organization_id, expired, @now)
      assert {:error, :invalid} = Token.renew(organization_id, nil, @now)
    end
  end

  test "a token signed with a key derived from secret_key_base is refused", %{
    organization_id: organization_id
  } do
    legacy_key =
      GlificWeb.Endpoint.config(:secret_key_base)
      |> KeyGenerator.generate("web_channel_contact_jwt", length: 32)

    token =
      %{"jti" => "s1", "sst" => @now}
      |> WebChannelLoginHelpers.claims(@now)
      |> WebChannelLoginHelpers.sign(legacy_key)

    assert {:error, :invalid} = Token.verify(organization_id, token, @now)
  end
end
