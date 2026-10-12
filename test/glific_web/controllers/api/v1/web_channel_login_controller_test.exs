defmodule GlificWeb.API.V1.WebChannelLoginControllerTest do
  @moduledoc false

  # Not async: it flips global FunWithFlags flags and writes the organization's credential.
  use GlificWeb.ConnCase

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Contacts.Identities,
    Fixtures,
    Repo,
    WebChannelFlagHelpers,
    WebChannelLoginHelpers
  }

  alias GlificWeb.WebChannel.Token

  @secret "ngo-login-secret-ngo-login-secret"

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    :ok
  end

  defp with_login_enabled(fun),
    do: WebChannelFlagHelpers.with_web_channel_login_enabled(1, %{"login_secret" => @secret}, fun)

  defp token(overrides \\ %{}),
    do: overrides |> WebChannelLoginHelpers.claims() |> WebChannelLoginHelpers.sign(@secret)

  defp login(conn, token),
    do: post(conn, Routes.api_v1_web_channel_login_path(conn, :login), %{"token" => token})

  defp provision(conn, token),
    do:
      post(conn, Routes.api_v1_web_channel_login_path(conn, :provision_contact), %{
        "token" => token
      })

  defp web_contacts_count do
    Contact |> where([c], is_nil(c.phone)) |> Repo.aggregate(:count)
  end

  describe "login" do
    test "creates the contact on a first login and returns the verify-otp shape", %{conn: conn} do
      with_login_enabled(fn ->
        assert %{"data" => data} = conn |> login(token(%{"name" => "Ravi"})) |> json_response(200)

        assert %{"token" => session_token, "contact_id" => contact_id, "name" => "Ravi"} = data
        assert Map.has_key?(data, "phone")
        assert data["phone"] == nil

        assert {:ok, %{contact_id: ^contact_id, org_id: 1}} =
                 Token.verify_contact_token(session_token)
      end)
    end

    test "a second login is the same contact", %{conn: conn} do
      with_login_enabled(fn ->
        first = conn |> login(token()) |> json_response(200)
        second = conn |> login(token()) |> json_response(200)

        assert first["data"]["contact_id"] == second["data"]["contact_id"]
      end)
    end

    test "links to the WhatsApp contact named by the phone claim", %{conn: conn} do
      with_login_enabled(fn ->
        contact = Fixtures.contact_fixture(%{phone: "919876500123"})

        assert %{"data" => %{"contact_id" => contact_id, "phone" => "919876500123"}} =
                 conn
                 |> login(token(%{"phone" => "+91 98765 00123"}))
                 |> json_response(200)

        assert contact_id == contact.id
      end)
    end

    test "a username equal to a phone number does not sign in that phone's contact", %{conn: conn} do
      with_login_enabled(fn ->
        contact = Fixtures.contact_fixture(%{phone: "919876500124"})
        Identities.ensure_web_phone_identity(contact)

        assert %{"data" => %{"contact_id" => contact_id, "phone" => nil}} =
                 conn |> login(token(%{"sub" => "919876500124"})) |> json_response(200)

        refute contact_id == contact.id
        assert %{kind: "ngo_username"} = Repo.get_by!(ContactIdentity, %{contact_id: contact_id})
      end)
    end

    test "a blocked contact can still log in", %{conn: conn} do
      with_login_enabled(fn ->
        contact = Fixtures.contact_fixture(%{status: :blocked})

        assert %{"data" => %{"contact_id" => contact_id}} =
                 conn |> login(token(%{"contact_id" => contact.id})) |> json_response(200)

        assert contact_id == contact.id
      end)
    end

    test "an invalid token is one generic 401, whatever is wrong with it", %{conn: conn} do
      with_login_enabled(fn ->
        bad_tokens = [
          "garbage",
          WebChannelLoginHelpers.sign(
            WebChannelLoginHelpers.claims(),
            "wrong-secret-wrong-secret-wrong"
          ),
          token(%{"channel" => "whatsapp"}),
          token(%{"exp" => System.system_time(:second) - 3_600})
        ]

        for bad <- bad_tokens do
          assert %{"error" => %{"status" => 401, "message" => "Invalid token"}} =
                   conn |> login(bad) |> json_response(401)
        end

        assert %{"error" => %{"status" => 401}} =
                 conn
                 |> post(Routes.api_v1_web_channel_login_path(conn, :login), %{})
                 |> json_response(401)
      end)
    end

    test "creates nothing for an invalid token", %{conn: conn} do
      with_login_enabled(fn ->
        before = web_contacts_count()
        conn |> login("garbage") |> json_response(401)
        assert before == web_contacts_count()
      end)
    end

    test "is refused with the login flag off, even with a valid token", %{conn: conn} do
      WebChannelFlagHelpers.with_web_channel_enabled(1, fn ->
        assert %{"error" => %{"status" => 404}} = conn |> login(token()) |> json_response(404)
        assert 0 == identity_count("ravi_12")
      end)
    end

    test "is refused with the web channel off, even with the login flag on", %{conn: conn} do
      with_login_enabled(fn ->
        FunWithFlags.disable(:web_channel_enabled, for_actor: %{organization_id: 1})
        1 |> Glific.Partners.organization() |> Glific.Partners.fill_cache()

        assert %{"error" => %{"status" => 404}} = conn |> login(token()) |> json_response(404)
        assert 0 == identity_count("ravi_12")
      end)
    end
  end

  describe "provision_contact" do
    test "creates the contact and returns only its id, with no session", %{conn: conn} do
      with_login_enabled(fn ->
        assert %{"data" => data} = conn |> provision(token()) |> json_response(200)

        assert %{"contact_id" => contact_id} = data
        assert map_size(data) == 1
        assert 1 == identity_count("ravi_12")
        assert %Contact{phone: nil} = Repo.get!(Contact, contact_id)
      end)
    end

    test "is idempotent", %{conn: conn} do
      with_login_enabled(fn ->
        first = conn |> provision(token()) |> json_response(200)
        second = conn |> provision(token()) |> json_response(200)

        assert first == second
        assert 1 == identity_count("ravi_12")
      end)
    end

    test "login afterwards signs in the provisioned contact", %{conn: conn} do
      with_login_enabled(fn ->
        provisioned = conn |> provision(token()) |> json_response(200)
        logged_in = conn |> login(token()) |> json_response(200)

        assert provisioned["data"]["contact_id"] == logged_in["data"]["contact_id"]
      end)
    end

    test "rejects an invalid token", %{conn: conn} do
      with_login_enabled(fn ->
        assert %{"error" => %{"status" => 401}} =
                 conn |> provision("garbage") |> json_response(401)
      end)
    end

    test "is refused with the login flag off", %{conn: conn} do
      WebChannelFlagHelpers.with_web_channel_enabled(1, fn ->
        assert %{"error" => %{"status" => 404}} = conn |> provision(token()) |> json_response(404)
      end)
    end
  end

  defp identity_count(identifier) do
    ContactIdentity
    |> where([i], i.kind == "ngo_username" and i.identifier == ^identifier)
    |> Repo.aggregate(:count)
  end
end
