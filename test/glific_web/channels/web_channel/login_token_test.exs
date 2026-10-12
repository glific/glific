defmodule GlificWeb.WebChannel.LoginTokenTest do
  # Not async: it flips the global `web_channel_enabled` and writes the organization's credential.
  use Glific.DataCase

  alias Glific.{WebChannelFlagHelpers, WebChannelLoginHelpers}
  alias GlificWeb.WebChannel.LoginToken

  @secret "current-secret-current-secret-0123"
  @previous_secret "previous-secret-previous-secret-01"
  @now 1_800_000_000

  setup %{organization_id: organization_id} do
    WebChannelFlagHelpers.activate_web_channel(organization_id, %{}, %{
      "login_secret" => @secret,
      "previous_login_secret" => @previous_secret
    })

    :ok
  end

  defp verify(organization_id, overrides, secret \\ @secret) do
    token =
      overrides |> WebChannelLoginHelpers.claims(@now) |> WebChannelLoginHelpers.sign(secret)

    LoginToken.verify(organization_id, token, @now)
  end

  test "accepts a valid token", %{organization_id: organization_id} do
    assert {:ok, %{sub: "ravi_12"} = claims} = verify(organization_id, %{})
    assert Map.keys(claims) == [:sub]
  end

  test "accepts a token signed with the previous secret", %{organization_id: organization_id} do
    assert {:ok, %{sub: "ravi_12"}} = verify(organization_id, %{}, @previous_secret)
  end

  test "rejects a token signed with any other secret", %{organization_id: organization_id} do
    assert {:error, :invalid} =
             verify(organization_id, %{}, "some-other-secret-some-other-secret")
  end

  test "rejects every token when no login secret is configured", %{
    organization_id: organization_id
  } do
    WebChannelFlagHelpers.activate_web_channel(organization_id, %{}, %{})

    assert {:error, :invalid} = verify(organization_id, %{})
  end

  test "rejects a previous secret once it is cleared", %{organization_id: organization_id} do
    WebChannelFlagHelpers.activate_web_channel(organization_id, %{}, %{"login_secret" => @secret})

    assert {:error, :invalid} = verify(organization_id, %{}, @previous_secret)
  end

  test "never trusts the token's algorithm", %{organization_id: organization_id} do
    claims = WebChannelLoginHelpers.claims(%{}, @now)

    assert {:error, :invalid} =
             LoginToken.verify(
               organization_id,
               WebChannelLoginHelpers.sign(claims, @secret, "HS512"),
               @now
             )

    unsigned = Base.url_encode64(~s({"alg":"none"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)

    assert {:error, :invalid} =
             LoginToken.verify(organization_id, "#{unsigned}.#{payload}.", @now)
  end

  test "rejects a token that is not a JWT", %{organization_id: organization_id} do
    assert {:error, :invalid} = LoginToken.verify(organization_id, "not-a-token", @now)
    assert {:error, :invalid} = LoginToken.verify(organization_id, "", @now)
    assert {:error, :invalid} = LoginToken.verify(organization_id, nil, @now)
  end

  test "rejects an organization that does not exist" do
    token = %{} |> WebChannelLoginHelpers.claims(@now) |> WebChannelLoginHelpers.sign(@secret)

    assert {:error, :invalid} = LoginToken.verify(0, token, @now)
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
    test "the lifetime may be an hour and no more", %{organization_id: organization_id} do
      assert {:ok, _} = verify(organization_id, %{"exp" => @now + 3_600})
      assert {:error, :invalid} = verify(organization_id, %{"exp" => @now + 3_601})
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
    test "name, phone and contact_id are returned", %{organization_id: organization_id} do
      assert {:ok, claims} =
               verify(organization_id, %{
                 "name" => "Ravi",
                 "phone" => "+91 98765 43210",
                 "contact_id" => 42
               })

      assert %{sub: "ravi_12", name: "Ravi", phone: "919876543210", contact_id: 42} == claims
    end

    test "an invalid phone is treated as absent", %{organization_id: organization_id} do
      assert {:ok, claims} = verify(organization_id, %{"phone" => "12"})
      refute Map.has_key?(claims, :phone)
    end

    test "a name over 255 characters or a non-integer contact_id is rejected", %{
      organization_id: organization_id
    } do
      assert {:error, :invalid} = verify(organization_id, %{"name" => String.duplicate("a", 256)})
      assert {:error, :invalid} = verify(organization_id, %{"contact_id" => "42"})
    end
  end

  test "reads the secrets of the organization the request is for", %{
    organization_id: organization_id
  } do
    other_organization = Glific.Fixtures.organization_fixture()
    Repo.put_organization_id(organization_id)

    assert {:error, :invalid} = verify(other_organization.id, %{})
  end
end
