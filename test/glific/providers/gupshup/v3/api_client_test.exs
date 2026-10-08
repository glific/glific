defmodule Glific.Providers.Gupshup.V3.ApiClientTest do
  use Glific.DataCase

  alias Glific.Caches
  alias Glific.Providers.Gupshup.PartnerAPI
  alias Glific.Providers.Gupshup.V3.ApiClient

  @message_body %{"messaging_product" => "whatsapp", "to" => "919917443994"}

  setup %{organization_id: organization_id} do
    Application.put_env(:glific, :gupshup_v3_req_plug, {Req.Test, ApiClient})

    # The token cache is shared by the whole suite and other Gupshup tests rely on what is in it.
    {:ok, app_token} = Caches.get(organization_id, "partner_app_token")
    {:ok, partner_token} = Caches.get(0, "partner_token")
    Caches.remove(organization_id, ["partner_app_token"])
    Caches.remove(0, ["partner_token"])

    on_exit(fn ->
      Application.delete_env(:glific, :gupshup_v3_req_plug)
      restore_cache(organization_id, "partner_app_token", app_token)
      restore_cache(0, "partner_token", partner_token)
    end)

    {:ok, app_id} = PartnerAPI.app_id(organization_id)
    %{app_id: app_id}
  end

  test "send_message/2 posts the body with the cached app token",
       %{organization_id: organization_id, app_id: app_id} do
    Caches.set(organization_id, "partner_app_token", "cached-app-token")

    Req.Test.stub(ApiClient, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/partner/app/#{app_id}/v3/message"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["cached-app-token"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == @message_body

      Req.Test.json(conn, %{"messages" => [%{"id" => "gupshup-v3-id"}]})
    end)

    assert {:ok, %Req.Response{status: 200, body: %{"messages" => [%{"id" => "gupshup-v3-id"}]}}} =
             ApiClient.send_message(organization_id, @message_body)
  end

  test "send_message/2 logs in and fetches the app token when none is cached",
       %{organization_id: organization_id, app_id: app_id} do
    token_path = "/partner/app/#{app_id}/token"
    message_path = "/partner/app/#{app_id}/v3/message"

    Req.Test.stub(ApiClient, fn conn ->
      case conn.request_path do
        "/partner/account/login" ->
          Req.Test.json(conn, %{"token" => "partner-token"})

        ^token_path ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["partner-token"]
          Req.Test.json(conn, %{"token" => %{"token" => "fresh-app-token"}})

        ^message_path ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["fresh-app-token"]
          Req.Test.json(conn, %{"messages" => [%{"id" => "gupshup-v3-id"}]})
      end
    end)

    assert {:ok, %Req.Response{status: 200}} =
             ApiClient.send_message(organization_id, @message_body)

    assert {:ok, "partner-token"} = Caches.get(0, "partner_token")
    assert {:ok, "fresh-app-token"} = Caches.get(organization_id, "partner_app_token")
  end

  test "send_message/2 returns an error without sending when the login fails",
       %{organization_id: organization_id} do
    Req.Test.stub(ApiClient, fn conn ->
      assert conn.request_path == "/partner/account/login"

      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"status" => "error", "message" => "Invalid credentials"})
    end)

    assert {:error, "Could not fetch the partner token" <> _} =
             ApiClient.send_message(organization_id, @message_body)
  end

  test "send_message/2 returns the 4xx response for the response handler",
       %{organization_id: organization_id} do
    Caches.set(organization_id, "partner_app_token", "cached-app-token")

    Req.Test.stub(ApiClient, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"error" => %{"code" => 132_000, "message" => "Param mismatch"}})
    end)

    assert {:ok, %Req.Response{status: 400}} =
             ApiClient.send_message(organization_id, @message_body)
  end

  test "send_message/2 returns the bare reason on a transport timeout",
       %{organization_id: organization_id} do
    Caches.set(organization_id, "partner_app_token", "cached-app-token")

    Req.Test.stub(ApiClient, &Req.Test.transport_error(&1, :timeout))

    assert {:error, :timeout} = ApiClient.send_message(organization_id, @message_body)
  end

  defp restore_cache(organization_id, key, value) when is_binary(value),
    do: Caches.set(organization_id, key, value)

  defp restore_cache(organization_id, key, _value), do: Caches.remove(organization_id, [key])
end
