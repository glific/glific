defmodule GlificWeb.WebChannelSocketTest do
  @moduledoc false
  use GlificWeb.ChannelCase

  alias Glific.{
    Contacts,
    Fixtures,
    Partners,
    WebChannelFixtures,
    WebChannelFlagHelpers,
    WebChannelLoginHelpers
  }

  alias GlificWeb.WebChannelSocket
  alias Plug.Crypto.KeyGenerator

  setup do
    %{contact: WebChannelFixtures.web_contact_fixture()}
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
      token =
        with_web_channel_enabled(fn -> WebChannelFixtures.web_channel_session_token(contact) end)

      assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: token)
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
        forged =
          contact
          |> WebChannelFixtures.web_channel_claims()
          |> WebChannelFixtures.sign_web_channel_claims(
            Base.encode64(:crypto.strong_rand_bytes(32))
          )

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: forged)
      end)
    end

    test "refuses a contact that no longer exists", %{contact: contact} do
      with_web_channel_enabled(fn ->
        token = WebChannelFixtures.web_channel_session_token(contact)
        Glific.Repo.delete!(contact)

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: token)
      end)
    end

    test "a session token never creates a contact", %{contact: contact} do
      with_web_channel_enabled(fn ->
        token = WebChannelFixtures.web_channel_session_token(contact)
        Glific.Repo.delete!(contact)

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: token)
        assert {:error, :not_found} = Contacts.fetch_by_identity(:web, contact.phone)
      end)
    end

    test "refuses a token signed with a key derived from secret_key_base", %{contact: contact} do
      with_web_channel_enabled(fn ->
        legacy_key =
          GlificWeb.Endpoint.config(:secret_key_base)
          |> KeyGenerator.generate("web_channel_contact_jwt", length: 32)

        legacy =
          contact
          |> WebChannelFixtures.web_channel_claims()
          |> WebChannelFixtures.sign_web_channel_claims(legacy_key)

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: legacy)
      end)
    end

    test "refuses every token when the organization has no secret", %{contact: contact} do
      with_web_channel_enabled(fn ->
        token = WebChannelFixtures.web_channel_session_token(contact)
        WebChannelFlagHelpers.remove_web_channel_secret(1)

        assert :error = WebChannelFixtures.web_channel_socket_fixture(contact, token: token)
      end)
    end

    test "refuses a session token on another organization's host", %{contact: contact} do
      other = Fixtures.organization_fixture(%{shortcode: "othersession"})
      WebChannelFlagHelpers.activate_web_channel(other.id)
      FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: other.id})
      other.id |> Partners.organization() |> Partners.fill_cache()

      try do
        with_web_channel_enabled(fn ->
          token = WebChannelFixtures.web_channel_session_token(contact)
          host = "othersession." <> Glific.base_domain()

          assert :error =
                   WebChannelFixtures.web_channel_socket_fixture(contact,
                     token: token,
                     host: host
                   )

          assert {:ok, _socket} =
                   WebChannelFixtures.web_channel_socket_fixture(contact, token: token)
        end)
      after
        WebChannelFlagHelpers.reset_web_channel_flag(other.id)
      end
    end

    test "refuses a missing token" do
      with_web_channel_enabled(fn ->
        assert :error = Phoenix.ChannelTest.connect(WebChannelSocket, %{})
      end)
    end

    test "connects once the flag is enabled, even though the organization was cached while it was off (#5662)",
         %{contact: contact} do
      organization_id = contact.organization_id

      # The organization's own half of the switch is already on and cached; this test is about
      # the flag alone.
      Glific.WebChannelFlagHelpers.activate_web_channel(organization_id)

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

  describe "connect/3 with an NGO token" do
    @secret "ngo-login-secret-ngo-login-secret"

    defp ngo_token(overrides \\ %{}, secret \\ @secret),
      do: overrides |> WebChannelLoginHelpers.claims() |> WebChannelLoginHelpers.sign(secret)

    defp with_signature_secret(fun),
      do:
        WebChannelFlagHelpers.with_web_channel_secrets(
          1,
          Glific.WebChannelFlagHelpers.jwt_signature_secrets([@secret]),
          fun
        )

    test "a new username creates the contact and its identity, and can talk" do
      with_signature_secret(fn ->
        assert {:ok, ws_socket} = WebChannelFixtures.connect_with_token(ngo_token())
        contact = ws_socket.assigns.current_contact

        assert contact.phone == nil
        assert {:ok, ^contact} = Contacts.fetch_by_identity(:web, "ravi_12")
        assert ws_socket.assigns.organization_id == 1
        assert is_integer(ws_socket.assigns.token_exp)

        {:ok, _reply, socket} = WebChannelFixtures.join_web_channel(ws_socket)
        ref = push(socket, "new_message", %{"body" => "hello"})
        assert_reply ref, :ok
      end)
    end

    test "usernames differing only in case are the same contact" do
      with_signature_secret(fn ->
        {:ok, first} = WebChannelFixtures.connect_with_token(ngo_token(%{"sub" => "Ravi_Web"}))
        {:ok, second} = WebChannelFixtures.connect_with_token(ngo_token(%{"sub" => "ravi_web"}))

        assert first.assigns.current_contact.id == second.assigns.current_contact.id
      end)
    end

    test "a returning username is the same contact" do
      with_signature_secret(fn ->
        {:ok, first} = WebChannelFixtures.connect_with_token(ngo_token())
        {:ok, second} = WebChannelFixtures.connect_with_token(ngo_token())

        assert first.assigns.current_contact.id == second.assigns.current_contact.id
        assert first.assigns.session_id == second.assigns.session_id
      end)
    end

    test "links to the WhatsApp contact named by the phone claim" do
      with_signature_secret(fn ->
        contact = Fixtures.contact_fixture(%{phone: "919876500555"})

        {:ok, socket} =
          WebChannelFixtures.connect_with_token(
            ngo_token(%{"sub" => "by_phone", "phone" => "919876500555"})
          )

        assert socket.assigns.current_contact.id == contact.id
      end)
    end

    test "refuses a wrong secret, an expired token and a wrong channel claim" do
      with_signature_secret(fn ->
        now = System.system_time(:second)

        for token <- [
              ngo_token(%{}, "wrong-secret-wrong-secret-wrong"),
              ngo_token(%{"iat" => now - 7_200, "exp" => now - 3_600}),
              ngo_token(%{"channel" => "whatsapp"}),
              "garbage"
            ] do
          assert :error = WebChannelFixtures.connect_with_token(token)
        end
      end)
    end

    test "accepts a lifetime of exactly 24 hours and refuses a longer one" do
      with_signature_secret(fn ->
        now = System.system_time(:second)

        assert {:ok, _socket} =
                 WebChannelFixtures.connect_with_token(
                   ngo_token(%{"iat" => now, "exp" => now + 86_400})
                 )

        assert :error =
                 WebChannelFixtures.connect_with_token(
                   ngo_token(%{"iat" => now, "exp" => now + 86_401})
                 )
      end)
    end

    test "refuses a token valid for another organization's secret on that organization's host" do
      other = Fixtures.organization_fixture(%{shortcode: "otherngo"})

      WebChannelFlagHelpers.activate_web_channel(
        other.id,
        %{},
        Glific.WebChannelFlagHelpers.jwt_signature_secrets(["other-secret-other-secret-other"])
      )

      FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: other.id})
      other.id |> Partners.organization() |> Partners.fill_cache()

      try do
        with_signature_secret(fn ->
          host = "otherngo." <> Glific.base_domain()

          assert :error = WebChannelFixtures.connect_with_token(ngo_token(), host: host)
          assert {:ok, _socket} = WebChannelFixtures.connect_with_token(ngo_token())
        end)
      after
        WebChannelFlagHelpers.reset_web_channel_flag(other.id)
      end
    end

    test "refuses a connection with no host" do
      with_signature_secret(fn ->
        assert :error =
                 Phoenix.ChannelTest.connect(WebChannelSocket, %{"token" => ngo_token()})
      end)
    end

    test "refuses when the web channel is off" do
      WebChannelFlagHelpers.activate_web_channel(
        1,
        %{},
        Glific.WebChannelFlagHelpers.jwt_signature_secrets([@secret])
      )

      assert :error = WebChannelFixtures.connect_with_token(ngo_token())
    end

    test "Glific's own token still connects", %{contact: contact} do
      with_signature_secret(fn ->
        assert {:ok, socket} = WebChannelFixtures.web_channel_socket_fixture(contact)
        assert socket.assigns.current_contact.id == contact.id
      end)
    end
  end

  describe "connect/3 rate limiting" do
    defp connect_from(contact, address) do
      WebChannelFixtures.web_channel_socket_fixture(contact,
        connect_info: %{x_headers: [{"x-forwarded-for", address}]}
      )
    end

    defp with_connect_limit(count, fun) do
      previous = Application.get_env(:glific, :rate_limit_web_channel_connect_ip)

      Application.put_env(:glific, :rate_limit_web_channel_connect_ip,
        scale_ms: 60_000,
        count: count
      )

      try do
        fun.()
      after
        Application.put_env(:glific, :rate_limit_web_channel_connect_ip, previous)
      end
    end

    test "refuses a connect flood from one address", %{contact: contact} do
      with_web_channel_enabled(fn ->
        with_connect_limit(2, fn ->
          assert {:ok, _socket} = connect_from(contact, "198.51.100.30")
          assert {:ok, _socket} = connect_from(contact, "198.51.100.30")
          assert :error = connect_from(contact, "198.51.100.30")
        end)
      end)
    end

    test "keeps a separate budget per address", %{contact: contact} do
      with_web_channel_enabled(fn ->
        with_connect_limit(1, fn ->
          assert {:ok, _socket} = connect_from(contact, "198.51.100.31")
          assert :error = connect_from(contact, "198.51.100.31")
          assert {:ok, _socket} = connect_from(contact, "198.51.100.32")
        end)
      end)
    end

    # Distinguishable on purpose: a busy node is about us, every other refusal is about them.
    test "refuses with server_busy once the node's total connect budget is spent", %{
      contact: contact
    } do
      previous = Application.get_env(:glific, :rate_limit_web_channel_connect_total)

      Application.put_env(:glific, :rate_limit_web_channel_connect_total,
        scale_ms: 60_000,
        count: 1
      )

      ExRated.delete_bucket("web_channel_connect:total")

      on_exit(fn ->
        Application.put_env(:glific, :rate_limit_web_channel_connect_total, previous)
        ExRated.delete_bucket("web_channel_connect:total")
      end)

      with_web_channel_enabled(fn ->
        assert {:ok, _socket} = connect_from(contact, "198.51.100.40")

        # A different address, so this can only be the total.
        assert {:error, :server_busy} = connect_from(contact, "198.51.100.41")
      end)
    end

    test "a bad token is still refused opaquely, not as server_busy", %{contact: _contact} do
      with_web_channel_enabled(fn ->
        assert :error =
                 connect(
                   WebChannelSocket,
                   %{"token" => "not-a-token"},
                   connect_info: %{x_headers: [{"x-forwarded-for", "198.51.100.42"}]}
                 )
      end)
    end

    # The address is charged before the token is looked at, so an unauthenticated flood cannot
    # make us do the verification work.
    test "charges the address even when the token is garbage", %{contact: contact} do
      with_web_channel_enabled(fn ->
        with_connect_limit(1, fn ->
          assert :error =
                   connect(
                     WebChannelSocket,
                     %{"token" => "not-a-token"},
                     connect_info: %{x_headers: [{"x-forwarded-for", "198.51.100.33"}]}
                   )

          assert :error = connect_from(contact, "198.51.100.33")
        end)
      end)
    end
  end
end
