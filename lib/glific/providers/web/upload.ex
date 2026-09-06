defmodule Glific.Providers.Web.Upload do
  @moduledoc """
  Validates URLs a web-channel browser contact's message claims to point at.

  The web channel now uploads straight into the organization's own GCS bucket via a pre-signed
  PUT URL (`Glific.GCS.SignedUrl`) — Glific itself never sees the bytes. This module is what is
  left once that upload is done: deriving the extension a signed object is named with, and
  checking that a URL a `new_media_message` socket event claims is one the organization's own
  bucket (or, in dev/test, the local-disk fallback) could actually have produced.
  """

  alias Glific.GCS

  @gcs_host "storage.googleapis.com"

  @doc """
  Derive a file extension from an already-validated content type — never from anything the
  caller supplies directly. An extension the client chooses is a filename it chooses:
  "../../x" writes outside the org's directory, and "html" turns an upload into same-origin
  script if the path is ever served.
  """
  @spec extension_for(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def extension_for(content_type) when is_binary(content_type) do
    content_type
    |> String.split(";")
    |> hd()
    |> String.trim()
    |> String.downcase()
    |> MIME.extensions()
    |> List.first()
    |> case do
      nil -> {:error, "media upload failed: unrecognised content type"}
      extension -> {:ok, extension}
    end
  end

  def extension_for(_content_type),
    do: {:error, "media upload failed: missing content type"}

  @doc """
  The GCS bucket and object name a previously-issued GCS URL points at, or `:error` if `url`
  isn't one of the organization's own GCS objects (this never matches a local-fallback URL,
  which has no bucket/object to look up).
  """
  @spec gcs_object(non_neg_integer(), String.t()) :: {:ok, String.t(), String.t()} | :error
  def gcs_object(organization_id, url) when is_binary(url) do
    with %URI{scheme: scheme, host: @gcs_host, path: path} when scheme in ["http", "https"] <-
           URI.parse(url),
         bucket when is_binary(bucket) <- GCS.bucket_name(organization_id),
         prefix = "/#{bucket}/",
         true <- String.starts_with?(path || "", prefix) do
      {:ok, bucket, path |> String.trim_leading(prefix) |> URI.decode()}
    else
      _ -> :error
    end
  end

  def gcs_object(_organization_id, _url), do: :error

  @doc """
  Whether `url` is one this module itself issued for `organization_id` — a GCS object under the
  organization's own bucket, or a locally-served upload under its own org directory.

  A raw client can push any URL into the `new_media_message` socket event; without this check
  it becomes a message the staff inbox renders and an admin clicks.
  """
  @spec issued_url?(non_neg_integer(), String.t()) :: boolean()
  def issued_url?(organization_id, url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: @gcs_host, path: path} when scheme in ["http", "https"] ->
        gcs_url?(organization_id, path)

      %URI{scheme: scheme, host: host, path: path} when scheme in ["http", "https"] ->
        local_url?(organization_id, host, path)

      _ ->
        false
    end
  end

  def issued_url?(_organization_id, _url), do: false

  @spec gcs_url?(non_neg_integer(), String.t() | nil) :: boolean()
  defp gcs_url?(organization_id, path) do
    case GCS.bucket_name(organization_id) do
      nil -> false
      bucket -> String.starts_with?(path || "", "/#{bucket}/")
    end
  end

  @spec local_url?(non_neg_integer(), String.t() | nil, String.t() | nil) :: boolean()
  defp local_url?(organization_id, host, path) do
    endpoint_host = GlificWeb.Endpoint.url() |> URI.parse() |> Map.get(:host)
    host == endpoint_host && String.starts_with?(path || "", "/uploads/#{organization_id}/")
  end
end
