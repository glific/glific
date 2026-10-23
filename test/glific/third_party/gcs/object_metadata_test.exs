defmodule Glific.GCS.ObjectMetadataTest do
  @moduledoc false
  use Glific.DataCase

  alias Glific.{GCS.ObjectMetadata, GcsFixtures}

  setup %{organization_id: organization_id} do
    {private_key_pem, _public_key} = GcsFixtures.generate_rsa_keypair()

    {:ok, _credential} =
      Glific.Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        secrets: %{
          "bucket" => "some-bucket",
          "service_account" =>
            Jason.encode!(%{
              "client_email" => "org@example.iam.gserviceaccount.com",
              "private_key" => private_key_pem
            })
        },
        is_active: true,
        organization_id: organization_id
      })

    :ok
  end

  describe "fetch/3" do
    test "returns the object's size and content type", %{organization_id: organization_id} do
      # A HEAD, not a GET: the size comes from the response headers, so the object body never
      # crosses the wire.
      Tesla.Mock.mock(fn %{method: :head, url: url} ->
        assert String.starts_with?(url, "https://storage.googleapis.com/some-bucket/object.png?")
        assert String.contains?(url, "X-Goog-Signature=")

        %Tesla.Env{
          status: 200,
          headers: [{"content-length", "12345"}, {"content-type", "image/png"}]
        }
      end)

      assert {:ok, %{size: 12_345, content_type: "image/png"}} =
               ObjectMetadata.fetch(organization_id, "some-bucket", "object.png")
    end

    test "keeps path separators in a nested object name", %{organization_id: organization_id} do
      Tesla.Mock.mock(fn %{method: :head, url: url} ->
        [path, _query] = String.split(url, "?", parts: 2)
        assert path == "https://storage.googleapis.com/some-bucket/uploads/object.png"

        %Tesla.Env{
          status: 200,
          headers: [{"content-length", "1"}, {"content-type", "image/png"}]
        }
      end)

      assert {:ok, _metadata} =
               ObjectMetadata.fetch(organization_id, "some-bucket", "uploads/object.png")
    end

    test "returns an error when the object does not exist", %{organization_id: organization_id} do
      Tesla.Mock.mock(fn %{method: :head} -> %Tesla.Env{status: 404, headers: []} end)

      assert {:error, {:http_status, 404}} =
               ObjectMetadata.fetch(organization_id, "some-bucket", "missing.png")
    end

    # A private bucket answers an unsigned or wrongly-signed read this way. It must be
    # distinguishable in the logs from a missing object, since the fixes differ entirely.
    test "returns an error when the read is refused", %{organization_id: organization_id} do
      Tesla.Mock.mock(fn %{method: :head} -> %Tesla.Env{status: 403, headers: []} end)

      assert {:error, {:http_status, 403}} =
               ObjectMetadata.fetch(organization_id, "some-bucket", "object.png")
    end

    test "returns an error when the response carries no length", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn %{method: :head} ->
        %Tesla.Env{status: 200, headers: [{"content-type", "image/png"}]}
      end)

      assert {:error, :invalid_response} =
               ObjectMetadata.fetch(organization_id, "some-bucket", "object.png")
    end

    test "returns an error on a network failure", %{organization_id: organization_id} do
      Tesla.Mock.mock(fn %{method: :head} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               ObjectMetadata.fetch(organization_id, "some-bucket", "object.png")
    end

    test "returns an error when the organization has no GCS credential" do
      other_organization_id = Glific.Fixtures.organization_fixture().id

      assert {:error, :gcs_not_configured} =
               ObjectMetadata.fetch(other_organization_id, "some-bucket", "object.png")
    end
  end
end
