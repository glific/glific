defmodule GlificWeb.API.V1.WebChannelContactControllerTest do
  @moduledoc false

  # Not async: it flips global FunWithFlags flags and writes the organization's credential.
  use GlificWeb.ConnCase

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Repo,
    WebChannelFlagHelpers,
    WebChannelLoginHelpers
  }

  @secret "ngo-login-secret-ngo-login-secret"

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    :ok
  end

  defp with_login_secret(fun),
    do: WebChannelFlagHelpers.with_web_channel_secrets(1, %{"login_secret" => @secret}, fun)

  defp token(overrides \\ %{}),
    do: overrides |> WebChannelLoginHelpers.claims() |> WebChannelLoginHelpers.sign(@secret)

  defp provision(conn, token),
    do:
      post(conn, Routes.api_v1_web_channel_contact_path(conn, :provision_contact), %{
        "token" => token
      })

  describe "provision_contact" do
    test "creates the contact and returns only its id, with no session", %{conn: conn} do
      with_login_secret(fn ->
        assert %{"data" => data} = conn |> provision(token()) |> json_response(200)

        assert %{"contact_id" => contact_id} = data
        assert map_size(data) == 1
        assert 1 == identity_count("ravi_12")
        assert %Contact{phone: nil} = Repo.get!(Contact, contact_id)
      end)
    end

    test "is idempotent", %{conn: conn} do
      with_login_secret(fn ->
        first = conn |> provision(token()) |> json_response(200)
        second = conn |> provision(token()) |> json_response(200)

        assert first == second
        assert 1 == identity_count("ravi_12")
      end)
    end

    test "a socket connect afterwards is the provisioned contact", %{conn: conn} do
      with_login_secret(fn ->
        %{"data" => %{"contact_id" => contact_id}} =
          conn |> provision(token()) |> json_response(200)

        assert {:ok, socket} = Glific.WebChannelFixtures.ngo_socket_fixture(token())
        assert socket.assigns.current_contact.id == contact_id
      end)
    end

    test "there is no login route" do
      assert %{plug: Absinthe.Plug} =
               Phoenix.Router.route_info(
                 GlificWeb.Router,
                 "POST",
                 "/api/v1/web_channel/login",
                 "localhost"
               )
    end

    test "rejects an invalid token", %{conn: conn} do
      with_login_secret(fn ->
        assert %{"error" => %{"status" => 401}} =
                 conn |> provision("garbage") |> json_response(401)
      end)
    end

    test "is refused with the web channel off", %{conn: conn} do
      assert %{"error" => %{"status" => 404}} = conn |> provision(token()) |> json_response(404)
    end
  end

  defp identity_count(identifier) do
    ContactIdentity
    |> where([i], i.channel == :web and i.identifier == ^identifier)
    |> Repo.aggregate(:count)
  end
end
