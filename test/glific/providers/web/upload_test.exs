defmodule Glific.Providers.Web.UploadTest do
  @moduledoc false
  use Glific.DataCase

  alias Glific.{Partners, Providers.Web.Upload}

  describe "issued_url?/2 — local media" do
    test "accepts a URL under the organization's own upload directory", %{
      organization_id: organization_id
    } do
      url = "#{GlificWeb.Endpoint.url()}/uploads/#{organization_id}/file.png"
      assert Upload.issued_url?(organization_id, url)
    end

    test "rejects a URL on the same host but under another organisation's directory", %{
      organization_id: organization_id
    } do
      url = "#{GlificWeb.Endpoint.url()}/uploads/#{organization_id + 1}/file.png"
      refute Upload.issued_url?(organization_id, url)
    end

    test "rejects a URL on an entirely different host", %{organization_id: organization_id} do
      refute Upload.issued_url?(organization_id, "https://evil.example.com/whatever.png")
    end

    test "rejects a non-http(s) scheme, a malformed URL, and a nil url", %{
      organization_id: organization_id
    } do
      refute Upload.issued_url?(organization_id, "ftp://#{GlificWeb.Endpoint.url()}/whatever.png")
      refute Upload.issued_url?(organization_id, "not a url")
      refute Upload.issued_url?(organization_id, nil)
    end
  end

  describe "issued_url?/2 — GCS" do
    setup %{organization_id: organization_id} do
      {:ok, _credential} =
        Partners.create_credential(%{
          shortcode: "google_cloud_storage",
          secrets: %{
            "bucket" => "org-#{organization_id}-bucket",
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        })

      :ok
    end

    test "accepts a URL under the organization's own configured bucket", %{
      organization_id: organization_id
    } do
      url =
        "https://storage.googleapis.com/org-#{organization_id}-bucket/outbound/2026-01/web_channel/file.png"

      assert Upload.issued_url?(organization_id, url)
    end

    test "rejects a URL on the same GCS host but under another organisation's bucket", %{
      organization_id: organization_id
    } do
      # A raw client can't be told apart from a legitimate one by host alone: every org's GCS
      # media lives under the same storage.googleapis.com host, so the bucket segment of the
      # path is the only thing that can tell one organisation's media from another's.
      url =
        "https://storage.googleapis.com/some-other-orgs-bucket/outbound/2026-01/web_channel/file.png"

      refute Upload.issued_url?(organization_id, url)
    end
  end
end
