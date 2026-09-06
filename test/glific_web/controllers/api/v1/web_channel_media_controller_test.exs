defmodule GlificWeb.API.V1.WebChannelMediaControllerTest do
  @moduledoc false

  # Not async: flips the global `web_channel_enabled` FunWithFlags flag, same constraint as
  # `web_channel_auth_controller_test.exs`.
  use GlificWeb.ConnCase

  alias Glific.{Contacts.Contact, Fixtures, GcsFixtures, WebChannelFlagHelpers}
  alias GlificWeb.WebChannel.Token

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    %{contact: Fixtures.contact_fixture()}
  end

  @spec with_web_channel_enabled((-> any())) :: any()
  defp with_web_channel_enabled(fun), do: WebChannelFlagHelpers.with_web_channel_enabled(1, fun)

  @spec configure_gcs(non_neg_integer()) :: :ok
  defp configure_gcs(organization_id) do
    {private_key_pem, _public_key} = GcsFixtures.generate_rsa_keypair()

    GcsFixtures.create_gcs_credential(
      organization_id,
      "org-#{organization_id}-bucket",
      "org-#{organization_id}@example.iam.gserviceaccount.com",
      private_key_pem
    )
  end

  describe "upload_url/2" do
    test "rejects a request with no Authorization header, producing no signature", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        configure_gcs(contact.organization_id)

        conn =
          post(conn, Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => 1024
          })

        assert json = json_response(conn, 401)
        refute get_in(json, ["data"])
      end)
    end

    test "rejects a garbage bearer token", %{conn: conn} do
      with_web_channel_enabled(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer not-a-token")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => 1024
          })

        assert json_response(conn, 401)
      end)
    end

    test "rejects a token for a different organisation", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        # web_channel_enabled is only on for org 1 (with_web_channel_enabled/1 above) — a token
        # naming a different org must not piggyback on that, even though it verifies fine (the
        # signing key is installation-wide today).
        other_organization_id = contact.organization_id + 1

        foreign_token =
          Token.sign_contact_token(%Contact{
            id: contact.id,
            organization_id: other_organization_id,
            phone: contact.phone
          })

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{foreign_token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => 1024
          })

        assert json_response(conn, 404)
      end)
    end

    test "returns 404 when the feature flag is off", %{conn: conn, contact: contact} do
      token = Token.sign_contact_token(contact)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
          "type" => "image",
          "content_type" => "image/png",
          "size" => 1024
        })

      assert json_response(conn, 404)
    end

    test "signs an upload URL for a valid request", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        configure_gcs(contact.organization_id)
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => 1024
          })

        assert json = json_response(conn, 200)
        upload_url = get_in(json, ["data", "upload_url"])
        url = get_in(json, ["data", "url"])

        assert String.starts_with?(
                 url,
                 "https://storage.googleapis.com/org-#{contact.organization_id}-bucket/"
               )

        assert String.starts_with?(upload_url, url <> "?")
        assert String.contains?(upload_url, "X-Goog-Signature=")
        assert get_in(json, ["data", "content_type"]) == "image/png"
        assert get_in(json, ["data", "expires_in"]) == 300
      end)
    end

    # The object name is a bare, server-derived UUID with an extension taken from the content
    # type — never anything the caller supplies — so a caller cannot escape the bucket's flat
    # namespace or smuggle a dangerous extension (e.g. "html") through this endpoint.
    test "derives the object's extension from the content type, ignoring anything the caller implies",
         %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        configure_gcs(contact.organization_id)
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => 1024
          })

        assert json = json_response(conn, 200)
        url = get_in(json, ["data", "url"])

        assert String.ends_with?(url, ".png")
        refute String.contains?(url, "..")
      end)
    end

    test "refuses a content type it cannot derive an extension from", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        configure_gcs(contact.organization_id)
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/not-a-real-subtype",
            "size" => 1024
          })

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "code"]) == "upload_failed"
      end)
    end

    test "rejects a content type outside the allowlist with a typed 415", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "text/plain",
            "size" => 1024
          })

        assert json = json_response(conn, 415)
        assert get_in(json, ["error", "code"]) == "unsupported_type"
      end)
    end

    test "rejects an oversized declared size with a typed 413", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            # media_size_limit("image") is 5120 KB; one byte over that in bytes.
            "size" => 5_120 * 1024 + 1
          })

        assert json = json_response(conn, 413)
        assert get_in(json, ["error", "code"]) == "file_too_large"
      end)
    end

    test "rejects a non-positive-integer size with a typed 422", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => -1
          })

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "code"]) == "invalid_size"
      end)
    end

    test "rejects an unsupported message type with a typed 415", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "sticker",
            "content_type" => "image/webp",
            "size" => 1024
          })

        assert json = json_response(conn, 415)
        assert get_in(json, ["error", "code"]) == "unsupported_type"
      end)
    end

    test "returns a typed 503 when no upload destination is configured for the organization", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload_url), %{
            "type" => "image",
            "content_type" => "image/png",
            "size" => 1024
          })

        assert json = json_response(conn, 503)
        assert get_in(json, ["error", "code"]) == "storage_unavailable"
      end)
    end
  end
end
