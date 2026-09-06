defmodule GlificWeb.API.V1.WebChannelMediaControllerTest do
  @moduledoc false

  # Not async: flips the global `web_channel_enabled` FunWithFlags flag, same constraint as
  # `web_channel_auth_controller_test.exs`.
  use GlificWeb.ConnCase

  alias Glific.{Contacts.Contact, Fixtures, WebChannelFlagHelpers}
  alias GlificWeb.WebChannel.Token

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    %{contact: Fixtures.contact_fixture()}
  end

  @spec with_web_channel_enabled((-> any())) :: any()
  defp with_web_channel_enabled(fun), do: WebChannelFlagHelpers.with_web_channel_enabled(1, fun)

  @spec upload_fixture(String.t(), String.t()) :: Plug.Upload.t()
  defp upload_fixture(content, content_type) do
    path =
      Path.join(System.tmp_dir!(), "web_channel_upload_#{System.unique_integer([:positive])}")

    File.write!(path, content)
    %Plug.Upload{path: path, content_type: content_type, filename: "upload"}
  end

  # `Providers.Web.Upload`'s local fallback (enabled globally in config/test.exs) writes real
  # files under this org directory, so a "rejected, writes nothing" assertion can count them
  # rather than trust the response status alone.
  @spec uploaded_file_count(non_neg_integer()) :: non_neg_integer()
  defp uploaded_file_count(organization_id) do
    dir =
      :glific
      |> Application.app_dir("priv/static/uploads")
      |> Path.join(to_string(organization_id))

    case File.ls(dir) do
      {:ok, files} -> length(files)
      {:error, _reason} -> 0
    end
  end

  describe "upload/2" do
    test "rejects a request with no Authorization header, writing nothing", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")
        before_count = uploaded_file_count(contact.organization_id)

        conn =
          post(conn, Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json_response(conn, 401)
        assert uploaded_file_count(contact.organization_id) == before_count
      end)
    end

    test "rejects a garbage bearer token", %{conn: conn} do
      with_web_channel_enabled(fn ->
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")

        conn =
          conn
          |> put_req_header("authorization", "Bearer not-a-token")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json_response(conn, 401)
      end)
    end

    test "rejects a token for a different organisation, writing nothing under either org", %{
      conn: conn,
      contact: contact
    } do
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

        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")
        before_count_own = uploaded_file_count(contact.organization_id)
        before_count_foreign = uploaded_file_count(other_organization_id)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{foreign_token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json_response(conn, 404)
        assert uploaded_file_count(contact.organization_id) == before_count_own
        assert uploaded_file_count(other_organization_id) == before_count_foreign
      end)
    end

    test "returns 404 when the feature flag is off", %{conn: conn, contact: contact} do
      token = Token.sign_contact_token(contact)
      upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
          "media" => upload,
          "type" => "image",
          "extension" => "png"
        })

      assert json_response(conn, 404)
    end

    test "uploads a valid image and returns its hosted URL", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json = json_response(conn, 200)
        assert url = get_in(json, ["data", "url"])
        assert String.contains?(url, "/uploads/#{contact.organization_id}/")
      end)
    end

    # The stored name is a filename the caller would otherwise choose: "../.." escapes the org's
    # directory, and "html" makes the upload same-origin script the moment anything serves it.
    test "ignores the caller's extension and derives one from the content type", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "../../../../escaped.html"
          })

        assert json = json_response(conn, 200)
        url = get_in(json, ["data", "url"])

        assert String.ends_with?(url, ".png")
        refute String.contains?(url, "..")
        assert String.contains?(url, "/uploads/#{contact.organization_id}/")
      end)
    end

    test "refuses a content type it cannot derive an extension from", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        before_count = uploaded_file_count(contact.organization_id)
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/not-a-real-subtype")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image"
          })

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "code"]) == "upload_failed"
        assert uploaded_file_count(contact.organization_id) == before_count
      end)
    end

    test "rejects a content type outside the allowlist with a typed 415", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        upload = upload_fixture("not really a png", "text/plain")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json = json_response(conn, 415)
        assert get_in(json, ["error", "code"]) == "unsupported_type"
      end)
    end

    test "rejects an oversized file with a typed 413", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        # media_size_limit("image") is 5120 KB; one byte over that in bytes.
        oversized = :binary.copy(<<0>>, 5_120 * 1024 + 1)
        upload = upload_fixture(oversized, "image/png")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json = json_response(conn, 413)
        assert get_in(json, ["error", "code"]) == "file_too_large"
      end)
    end

    test "rejects an unsupported message type with a typed 415", %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/webp")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "sticker",
            "extension" => "webp"
          })

        assert json = json_response(conn, 415)
        assert get_in(json, ["error", "code"]) == "unsupported_type"
      end)
    end

    test "rejects an oversized document with a typed 413, proving the multipart parser cap does not disagree with the document size cap",
         %{conn: conn, contact: contact} do
      with_web_channel_enabled(fn ->
        token = Token.sign_contact_token(contact)

        # Messages.media_size_limit("document") is 102_400 KB (104_857_600 bytes). One byte
        # over that, but comfortably under the endpoint's 110_000_000 byte multipart cap for
        # this route (lib/glific_web/endpoint.ex's @parser_for_web_channel_upload) — so this
        # request must reach the controller's typed 413, not die as an untyped parser error.
        oversized = :binary.copy(<<0>>, 102_400 * 1024 + 1)
        upload = upload_fixture(oversized, "application/pdf")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "document",
            "extension" => "pdf"
          })

        assert json = json_response(conn, 413)
        assert get_in(json, ["error", "code"]) == "file_too_large"
      end)
    end

    test "returns a typed 422 when no upload destination is configured for the organization", %{
      conn: conn,
      contact: contact
    } do
      with_web_channel_enabled(fn ->
        original_local_media = Application.get_env(:glific, :web_channel_local_media)
        Application.put_env(:glific, :web_channel_local_media, false)

        on_exit(fn ->
          Application.put_env(:glific, :web_channel_local_media, original_local_media)
        end)

        token = Token.sign_contact_token(contact)
        upload = upload_fixture(:binary.copy(<<0>>, 1024), "image/png")

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(Routes.api_v1_web_channel_media_path(conn, :upload), %{
            "media" => upload,
            "type" => "image",
            "extension" => "png"
          })

        assert json = json_response(conn, 422)
        assert get_in(json, ["error", "code"]) == "upload_failed"
      end)
    end
  end
end
