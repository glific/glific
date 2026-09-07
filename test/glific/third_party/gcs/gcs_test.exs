defmodule Glific.GCSTest do
  @moduledoc false
  use Glific.DataCase

  alias Glific.{GCS, GcsFixtures}

  describe "get_signed_url/3" do
    test "signs a GET url through the organization's own private-bucket credential", %{
      organization_id: organization_id
    } do
      {private_key_pem, _public_key} = GcsFixtures.generate_rsa_keypair()
      email = "org-#{organization_id}@example.iam.gserviceaccount.com"

      {:ok, _credential} =
        Glific.Partners.create_credential(%{
          shortcode: "google_cloud_storage",
          secrets: %{
            "bucket" => "org-#{organization_id}-public-bucket",
            "private_bucket" => "org-#{organization_id}-private-bucket",
            "service_account" =>
              Jason.encode!(%{"client_email" => email, "private_key" => private_key_pem})
          },
          is_active: true,
          organization_id: organization_id
        })

      assert {:ok, url} = GCS.get_signed_url("some/private-file.pdf", organization_id)
      assert String.contains?(url, "org-#{organization_id}-private-bucket")
      assert String.contains?(url, "X-Goog-Expires=300")

      # This function used to hardcode `"private_bucket" => "test-private-cc"`.
      refute String.contains?(url, "test-private-cc")
      assert String.starts_with?(url, "https://storage.googleapis.com/")
    end

    test "returns no_private_bucket when the organization has no private bucket configured", %{
      organization_id: organization_id
    } do
      {private_key_pem, _public_key} = GcsFixtures.generate_rsa_keypair()

      {:ok, _credential} =
        Glific.Partners.create_credential(%{
          shortcode: "google_cloud_storage",
          secrets: %{
            "bucket" => "org-#{organization_id}-public-bucket",
            "service_account" =>
              Jason.encode!(%{
                "client_email" => "x@example.com",
                "private_key" => private_key_pem
              })
          },
          is_active: true,
          organization_id: organization_id
        })

      assert {:error, :no_private_bucket} =
               GCS.get_signed_url("some/private-file.pdf", organization_id)
    end

    test "respects an :expires_in override", %{organization_id: organization_id} do
      {private_key_pem, _public_key} = GcsFixtures.generate_rsa_keypair()

      {:ok, _credential} =
        Glific.Partners.create_credential(%{
          shortcode: "google_cloud_storage",
          secrets: %{
            "bucket" => "org-#{organization_id}-public-bucket",
            "private_bucket" => "org-#{organization_id}-private-bucket",
            "service_account" =>
              Jason.encode!(%{
                "client_email" => "x@example.com",
                "private_key" => private_key_pem
              })
          },
          is_active: true,
          organization_id: organization_id
        })

      assert {:ok, url} = GCS.get_signed_url("f.pdf", organization_id, expires_in: 60)
      assert String.contains?(url, "X-Goog-Expires=60")
    end
  end

  describe "get_signed_url/3 — concurrency" do
    test "two organizations calling get_signed_url/3 at the same time each get their own credential" do
      organization_a = Repo.get_organization_id()
      organization_b = Glific.Fixtures.organization_fixture().id

      {private_key_a, _public_key_a} = GcsFixtures.generate_rsa_keypair()
      {private_key_b, _public_key_b} = GcsFixtures.generate_rsa_keypair()

      configure_private_bucket(organization_a, "bucket-a", "org-a@example.com", private_key_a)
      configure_private_bucket(organization_b, "bucket-b", "org-b@example.com", private_key_b)

      # A barrier, not a hope: both block on the same release message so the calls really
      # overlap rather than running one after the other.
      run = fn organization_id, expected_bucket ->
        Task.async(fn ->
          receive do
            :go -> :ok
          end

          {expected_bucket, GCS.get_signed_url("f.pdf", organization_id)}
        end)
      end

      task_a = run.(organization_a, "bucket-a")
      task_b = run.(organization_b, "bucket-b")

      send(task_a.pid, :go)
      send(task_b.pid, :go)

      for {expected_bucket, result} <- [Task.await(task_a), Task.await(task_b)] do
        {other_bucket, expected_email, other_email} =
          if expected_bucket == "bucket-a",
            do: {"bucket-b", "org-a@example.com", "org-b@example.com"},
            else: {"bucket-a", "org-b@example.com", "org-a@example.com"}

        assert {:ok, url} = result
        assert String.contains?(url, expected_bucket)
        refute String.contains?(url, other_bucket)

        # The bucket was always per-caller; the identity is what was shared, so
        # `X-Goog-Credential` is the assertion that bites.
        assert String.contains?(url, URI.encode(expected_email, &URI.char_unreserved?/1))
        refute String.contains?(url, URI.encode(other_email, &URI.char_unreserved?/1))
      end
    end
  end

  @spec configure_private_bucket(non_neg_integer(), String.t(), String.t(), String.t()) :: :ok
  defp configure_private_bucket(organization_id, private_bucket, email, private_key_pem) do
    {:ok, _credential} =
      Glific.Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        secrets: %{
          "bucket" => "#{private_bucket}-public",
          "private_bucket" => private_bucket,
          "service_account" =>
            Jason.encode!(%{"client_email" => email, "private_key" => private_key_pem})
        },
        is_active: true,
        organization_id: organization_id
      })

    :ok
  end
end
