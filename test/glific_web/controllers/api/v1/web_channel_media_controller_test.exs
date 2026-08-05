defmodule GlificWeb.API.V1.WebChannelMediaControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Fixtures
  alias GlificWeb.WebChannel.Token

  setup %{organization_id: organization_id} do
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    token = Token.sign_contact_token(contact)

    source_path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}.png")
    File.write!(source_path, "fake image bytes")
    on_exit(fn -> File.rm(source_path) end)

    %{contact: contact, token: token, source_path: source_path}
  end

  @spec media_upload(String.t()) :: Plug.Upload.t()
  defp media_upload(source_path) do
    %Plug.Upload{path: source_path, filename: "x.png", content_type: "image/png"}
  end

  describe "upload/2" do
    test "returns 200 with the hosted url for an authenticated upload", %{
      conn: conn,
      token: token,
      source_path: source_path
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/web_channel/upload", %{
          "media" => media_upload(source_path),
          "extension" => "png"
        })

      response = json_response(conn, 200)
      assert url = response["data"]["url"]
      assert url =~ "/uploads/"
      assert response["data"]["content_type"] == "image/png"

      relative_path = url |> String.split("/uploads/") |> List.last()

      written_path =
        Path.join([Application.app_dir(:glific, "priv/static/uploads"), relative_path])

      on_exit(fn -> File.rm(written_path) end)
    end

    test "returns 401 with a missing Authorization header", %{
      conn: conn,
      source_path: source_path
    } do
      conn =
        post(conn, "/api/v1/web_channel/upload", %{
          "media" => media_upload(source_path),
          "extension" => "png"
        })

      response = json_response(conn, 401)
      assert response["error"]["message"] == "Unauthorized"
    end

    test "returns 401 with an invalid token", %{conn: conn, source_path: source_path} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> post("/api/v1/web_channel/upload", %{
          "media" => media_upload(source_path),
          "extension" => "png"
        })

      response = json_response(conn, 401)
      assert response["error"]["message"] == "Unauthorized"
    end

    test "returns 422 when the media param is missing", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/web_channel/upload", %{"extension" => "png"})

      response = json_response(conn, 422)
      assert response["error"]["message"]
    end
  end
end
