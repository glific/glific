defmodule Glific.GCS.SignedUrlTest do
  @moduledoc false
  use Glific.DataCase

  alias Glific.{Fixtures, GCS.SignedUrl, GcsFixtures}

  defdelegate generate_rsa_keypair, to: GcsFixtures

  defdelegate create_gcs_credential(organization_id, bucket, email, private_key_pem),
    to: GcsFixtures

  # Reconstructs the V4 string-to-sign independently of `SignedUrl`'s own implementation (rather
  # than reusing its private functions), so a passing assertion means the URL is verifiable by
  # an outside party reading the spec, not just self-consistent with the code that produced it.
  @spec verify_v4_signature(String.t(), String.t(), String.t() | nil, tuple()) :: boolean()
  defp verify_v4_signature(full_url, method, content_type, public_key) do
    uri = URI.parse(full_url)
    query = URI.decode_query(uri.query)

    signature = query |> Map.fetch!("X-Goog-Signature") |> Base.decode16!(case: :lower)
    request_timestamp = Map.fetch!(query, "X-Goog-Date")
    credential = Map.fetch!(query, "X-Goog-Credential")
    [_email, datestamp, "auto", "storage", "goog4_request"] = String.split(credential, "/")
    credential_scope = "#{datestamp}/auto/storage/goog4_request"

    canonical_query_string =
      query
      |> Map.delete("X-Goog-Signature")
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("&", fn {key, value} ->
        "#{URI.encode(key, &URI.char_unreserved?/1)}=#{URI.encode(value, &URI.char_unreserved?/1)}"
      end)

    {canonical_headers, signed_headers} =
      if content_type,
        do: {"content-type:#{content_type}\nhost:storage.googleapis.com\n", "content-type;host"},
        else: {"host:storage.googleapis.com\n", "host"}

    canonical_request =
      Enum.join(
        [
          method,
          uri.path,
          canonical_query_string,
          canonical_headers,
          signed_headers,
          "UNSIGNED-PAYLOAD"
        ],
        "\n"
      )

    hash = :sha256 |> :crypto.hash(canonical_request) |> Base.encode16(case: :lower)

    string_to_sign =
      Enum.join(["GOOG4-RSA-SHA256", request_timestamp, credential_scope, hash], "\n")

    :public_key.verify(string_to_sign, :sha256, signature, public_key)
  end

  describe "signed_put_url/5" do
    setup %{organization_id: organization_id} do
      {private_key_pem, public_key} = generate_rsa_keypair()
      bucket = "org-#{organization_id}-bucket"
      email = "org-#{organization_id}@example.iam.gserviceaccount.com"
      create_gcs_credential(organization_id, bucket, email, private_key_pem)

      %{bucket: bucket, email: email, public_key: public_key}
    end

    test "signs a PUT url whose signature verifies against the organization's own key", %{
      organization_id: organization_id,
      bucket: bucket,
      email: email,
      public_key: public_key
    } do
      assert {:ok, %{upload_url: upload_url, url: url}} =
               SignedUrl.signed_put_url(
                 organization_id,
                 bucket,
                 "some-object.png",
                 "image/png",
                 300
               )

      assert url == "https://storage.googleapis.com/#{bucket}/some-object.png"
      assert String.starts_with?(upload_url, url <> "?")
      assert String.contains?(upload_url, "X-Goog-Algorithm=GOOG4-RSA-SHA256")
      assert String.contains?(upload_url, "X-Goog-SignedHeaders=content-type%3Bhost")
      assert String.contains?(upload_url, "X-Goog-Expires=300")
      assert String.contains?(upload_url, URI.encode(email, &URI.char_unreserved?/1))
      assert verify_v4_signature(upload_url, "PUT", "image/png", public_key)
    end

    test "a URL signed for one content type does not verify against another", %{
      organization_id: organization_id,
      bucket: bucket,
      public_key: public_key
    } do
      assert {:ok, %{upload_url: upload_url}} =
               SignedUrl.signed_put_url(
                 organization_id,
                 bucket,
                 "some-object.png",
                 "image/png",
                 300
               )

      refute verify_v4_signature(upload_url, "PUT", "image/jpeg", public_key)
    end

    test "a URL signed for one object name does not verify against another", %{
      organization_id: organization_id,
      bucket: bucket,
      public_key: public_key
    } do
      assert {:ok, %{upload_url: upload_url}} =
               SignedUrl.signed_put_url(
                 organization_id,
                 bucket,
                 "some-object.png",
                 "image/png",
                 300
               )

      uri = URI.parse(upload_url)

      tampered =
        URI.to_string(%{
          uri
          | path: String.replace(uri.path, "some-object.png", "other-object.png")
        })

      refute verify_v4_signature(tampered, "PUT", "image/png", public_key)
    end

    test "returns gcs_not_configured when the organization has no GCS credential" do
      other_organization = Fixtures.organization_fixture()

      assert {:error, :gcs_not_configured} =
               SignedUrl.signed_put_url(
                 other_organization.id,
                 "some-bucket",
                 "x.png",
                 "image/png",
                 300
               )
    end

    test "returns signing_failed for a malformed private key" do
      organization_id = Fixtures.organization_fixture().id
      bucket = "org-#{organization_id}-bucket"
      create_gcs_credential(organization_id, bucket, "bad@example.com", "not a pem")

      assert {:error, :signing_failed} =
               SignedUrl.signed_put_url(organization_id, bucket, "x.png", "image/png", 300)
    end
  end

  describe "signed_get_url/4" do
    setup %{organization_id: organization_id} do
      {private_key_pem, public_key} = generate_rsa_keypair()
      bucket = "org-#{organization_id}-bucket"
      email = "org-#{organization_id}@example.iam.gserviceaccount.com"
      create_gcs_credential(organization_id, bucket, email, private_key_pem)

      %{bucket: bucket, public_key: public_key}
    end

    test "signs a GET url, signing only the host header", %{
      organization_id: organization_id,
      bucket: bucket,
      public_key: public_key
    } do
      assert {:ok, url} =
               SignedUrl.signed_get_url(organization_id, bucket, "private-file.pdf", 300)

      assert String.contains?(url, "X-Goog-SignedHeaders=host")
      refute String.contains?(url, "content-type")
      assert verify_v4_signature(url, "GET", nil, public_key)
    end
  end

  describe "concurrent signing across organizations" do
    test "each organization's concurrent signature is signed by its own key, never the other's" do
      organization_a = Repo.get_organization_id()
      organization_b = Fixtures.organization_fixture().id

      {private_key_a, public_key_a} = generate_rsa_keypair()
      {private_key_b, public_key_b} = generate_rsa_keypair()

      create_gcs_credential(organization_a, "bucket-a", "org-a@example.com", private_key_a)
      create_gcs_credential(organization_b, "bucket-b", "org-b@example.com", private_key_b)

      orgs = [
        {organization_a, "bucket-a", public_key_a, public_key_b},
        {organization_b, "bucket-b", public_key_b, public_key_a}
      ]

      results =
        1..20
        |> Enum.flat_map(fn _ -> orgs end)
        |> Task.async_stream(
          fn {organization_id, bucket, own_key, other_key} ->
            {:ok, %{upload_url: upload_url}} =
              SignedUrl.signed_put_url(organization_id, bucket, "object.png", "image/png", 300)

            {upload_url, own_key, other_key}
          end,
          max_concurrency: 8,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      for {upload_url, own_key, other_key} <- results do
        assert verify_v4_signature(upload_url, "PUT", "image/png", own_key)
        refute verify_v4_signature(upload_url, "PUT", "image/png", other_key)
      end
    end
  end
end
