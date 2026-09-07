defmodule GlificWeb.WebChannelSocketTest do
  @moduledoc false
  use GlificWeb.ChannelCase

  alias Glific.{Fixtures, Partners, WebChannelFixtures}
  alias GlificWeb.WebChannel.Token
  alias GlificWeb.WebChannelSocket

  setup do
    %{contact: Fixtures.contact_fixture()}
  end

  describe "connect/3" do
    test "authenticates a contact with a valid token", %{contact: contact} do
      with_web_channel_enabled(fn ->
        assert {:ok, socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        assert socket.assigns.current_contact.id == contact.id
        assert socket.assigns.organization_id == contact.organization_id
        assert is_integer(socket.assigns.token_exp)
        assert is_binary(socket.assigns.session_id)
        assert is_integer(socket.assigns.session_started_at)
      end)
    end

    test "refuses to connect when the feature flag is off (the ChannelCase default)", %{
      contact: contact
    } do
      assert :error = WebChannelFixtures.web_channel_socket_fixture(contact)
    end

    test "refuses an expired token", %{contact: contact} do
      with_web_channel_enabled(fn ->
        now = System.system_time(:second)

        expired =
          contact
          |> WebChannelFixtures.web_channel_claims(%{
            "sst" => now - 7_200,
            "iat" => now - 7_200,
            "exp" => now - 60
          })
          |> WebChannelFixtures.sign_web_channel_claims()

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: expired)
      end)
    end

    test "refuses a forged token", %{contact: contact} do
      with_web_channel_enabled(fn ->
        foreign_key = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))

        forged =
          contact
          |> WebChannelFixtures.web_channel_claims()
          |> WebChannelFixtures.sign_web_channel_claims(foreign_key)

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: forged)
      end)
    end

    test "refuses a contact that no longer exists", %{contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        Glific.Repo.delete!(contact)

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: token)
      end)
    end

    test "refuses a missing token" do
      with_web_channel_enabled(fn ->
        assert :error = Phoenix.ChannelTest.connect(WebChannelSocket, %{})
      end)
    end

    test "connects once the flag is enabled, even though the organization was cached while it was off (#5662)",
         %{contact: contact} do
      organization_id = contact.organization_id

      # Confirm the cached field really is stale before proving the socket ignores it.
      cached = Partners.organization(organization_id)
      assert cached.web_channel_enabled == false

      # Flipped without refilling the cache: reading the virtual field would still see false.
      FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: organization_id})

      try do
        assert {:ok, _socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
      after
        Glific.WebChannelFlagHelpers.reset_web_channel_flag(organization_id)
      end
    end
  end
end
