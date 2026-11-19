defmodule Glific.GCS.SignedUrl do
  @moduledoc """
  Signs GCS V4 URLs directly from an organization's own service-account key, taken as an
  argument rather than read back off shared state.

  `GCS.load_goth/1` (removed) and waffle's `Waffle.Storage.Google.UrlV2` signer both stash
  `client_email`/`private_key` in `Goth.Config`, a single GenServer slot shared by every
  organization in the node — two organizations signing around the same time can interleave
  their writes with each other's reads and end up signing with the wrong identity. This module
  takes the credential as a plain function argument, so nothing here is shared across callers.

  Implements the "Signing URLs manually" V4 process (canonical request, `GOOG4-RSA-SHA256`
  string-to-sign, RSA-SHA256 over it via `:public_key.sign/3`) rather than going through waffle,
  since waffle's signer only ever produces `GET` URLs.
  """

  alias Glific.GCS

  @host "storage.googleapis.com"
  @algorithm "GOOG4-RSA-SHA256"

  @doc """
  A V4-signed PUT URL for `object_name` in `bucket`, usable only for exactly `content_type` and
  only within `expires_in` seconds — a client cannot reuse it for a different object or content
  type than it was signed for.
  """
  @spec signed_put_url(non_neg_integer(), String.t(), String.t(), String.t(), pos_integer()) ::
          {:ok, %{upload_url: String.t(), url: String.t()}}
          | {:error, :gcs_not_configured | :signing_failed}
  def signed_put_url(organization_id, bucket, object_name, content_type, expires_in) do
    with {:ok, credential} <- fetch_credential(organization_id) do
      sign("PUT", bucket, object_name, content_type, expires_in, credential)
    end
  end

  @doc """
  A V4-signed GET URL for `object_name` in `bucket`, valid for `expires_in` seconds.
  """
  @spec signed_get_url(non_neg_integer(), String.t(), String.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, :gcs_not_configured | :signing_failed}
  def signed_get_url(organization_id, bucket, object_name, expires_in) do
    with {:ok, credential} <- fetch_credential(organization_id),
         {:ok, %{upload_url: url}} <-
           sign("GET", bucket, object_name, nil, expires_in, credential) do
      {:ok, url}
    end
  end

  @doc """
  A V4-signed HEAD URL for `object_name` in `bucket`, valid for `expires_in` seconds.

  Used to read an object's size and content type without downloading it, and without depending on
  the bucket being publicly readable.
  """
  @spec signed_head_url(non_neg_integer(), String.t(), String.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, :gcs_not_configured | :signing_failed}
  def signed_head_url(organization_id, bucket, object_name, expires_in) do
    with {:ok, credential} <- fetch_credential(organization_id),
         {:ok, %{upload_url: url}} <-
           sign("HEAD", bucket, object_name, nil, expires_in, credential) do
      {:ok, url}
    end
  end

  @spec fetch_credential(non_neg_integer()) ::
          {:ok, %{email: String.t(), private_key: String.t()}} | {:error, :gcs_not_configured}
  defp fetch_credential(organization_id) do
    with %{"service_account" => json} when is_binary(json) <- GCS.get_secrets(organization_id),
         {:ok, %{"client_email" => email, "private_key" => private_key}}
         when is_binary(email) and is_binary(private_key) <- Jason.decode(json) do
      {:ok, %{email: email, private_key: private_key}}
    else
      _ -> {:error, :gcs_not_configured}
    end
  end

  @spec sign(String.t(), String.t(), String.t(), String.t() | nil, pos_integer(), map()) ::
          {:ok, %{upload_url: String.t(), url: String.t()}} | {:error, :signing_failed}
  defp sign(method, bucket, object_name, content_type, expires_in, %{
         email: email,
         private_key: private_key
       }) do
    now = DateTime.utc_now()
    request_timestamp = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    credential_scope = "#{Calendar.strftime(now, "%Y%m%d")}/auto/storage/goog4_request"
    canonical_uri = "/#{bucket}/#{encode_object_path(object_name)}"

    {canonical_headers, signed_headers} = headers(content_type)

    query_string =
      canonical_query_string(%{
        "X-Goog-Algorithm" => @algorithm,
        "X-Goog-Credential" => "#{email}/#{credential_scope}",
        "X-Goog-Date" => request_timestamp,
        "X-Goog-Expires" => to_string(expires_in),
        "X-Goog-SignedHeaders" => signed_headers
      })

    canonical_request =
      Enum.join(
        [
          method,
          canonical_uri,
          query_string,
          canonical_headers,
          signed_headers,
          "UNSIGNED-PAYLOAD"
        ],
        "\n"
      )

    string_to_sign =
      Enum.join(
        [@algorithm, request_timestamp, credential_scope, hex_sha256(canonical_request)],
        "\n"
      )

    with {:ok, signature} <- rsa_sign_hex(string_to_sign, private_key) do
      {:ok,
       %{
         upload_url:
           "https://#{@host}#{canonical_uri}?#{query_string}&X-Goog-Signature=#{signature}",
         url: "https://#{@host}#{canonical_uri}"
       }}
    end
  end

  @spec headers(String.t() | nil) :: {String.t(), String.t()}
  defp headers(nil), do: {"host:#{@host}\n", "host"}

  defp headers(content_type),
    do: {"content-type:#{content_type}\nhost:#{@host}\n", "content-type;host"}

  @spec canonical_query_string(map()) :: String.t()
  defp canonical_query_string(query) do
    query
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("&", fn {key, value} -> "#{uri_encode(key)}=#{uri_encode(value)}" end)
  end

  # V4 requires strict RFC3986-unreserved encoding; `URI.encode/1`'s default leaves `;` and `/`.
  @spec uri_encode(String.t()) :: String.t()
  defp uri_encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  # The one place `/` must survive, or the signature names an object containing "%2F".
  @spec encode_object_path(String.t()) :: String.t()
  defp encode_object_path(object_name),
    do: object_name |> String.split("/") |> Enum.map_join("/", &uri_encode/1)

  @spec hex_sha256(String.t()) :: String.t()
  defp hex_sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  # The rescue discards the exception term rather than surfacing it: it can hold the key.
  @spec rsa_sign_hex(String.t(), String.t()) :: {:ok, String.t()} | {:error, :signing_failed}
  defp rsa_sign_hex(string_to_sign, private_key_pem) do
    [entry] = :public_key.pem_decode(private_key_pem)
    key = :public_key.pem_entry_decode(entry)
    {:ok, string_to_sign |> :public_key.sign(:sha256, key) |> Base.encode16(case: :lower)}
  rescue
    _ -> {:error, :signing_failed}
  catch
    _, _ -> {:error, :signing_failed}
  end
end
