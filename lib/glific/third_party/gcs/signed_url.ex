defmodule Glific.GCS.SignedUrl do
  @moduledoc """
  This is an implementation of the v2 URL signing for Google Cloud Storage. See
  [the Google documentation](https://cloud.google.com/storage/docs/access-control/signed-urls-v2)
  for more details.

  The bulk of the major logic is taken from Martide's `arc_gcs` work:
  https://github.com/martide/arc_gcs.
  """

  use Waffle.Storage.Google.Url

  alias Waffle.Types
  alias Waffle.Storage.Google.{CloudStorage, Util}

  # Default expiration time is 3600 seconds, or 1 hour
  @default_expiry 3600

  # It's unlikely, but in the event that someone accidentally tries to give a
  # zero or negative expiration time, this will be used to correct that mistake
  @min_expiry 1

  # Maximum expiration time is 7 days from the creation of the signed URL
  @max_expiry 604_800

  # The official Google Cloud Storage host
  @endpoint "storage.googleapis.com"

  @doc """
  Returns the amount of time, in seconds, before a signed URL becomes invalid.
  Assumes the key for the option is `:expires_in`.
  """
  @spec expiry(Keyword.t()) :: pos_integer
  def expiry(opts \\ []) do
    case Util.option(opts, :expires_in, @default_expiry) do
      val when val < @min_expiry -> @min_expiry
      val when val > @max_expiry -> @max_expiry
      val -> val
    end
  end

  @doc """
  Determines whether or not the URL should be signed. Assumes the key for the
  option is `:signed`.
  """
  @spec signed?(Keyword.t()) :: boolean
  def signed?(opts \\ []), do: Util.option(opts, :signed, false)

  @doc """
  Returns the remote asset host. The config key is assumed to be `:asset_host`.
  """
  @spec endpoint(Keyword.t()) :: String.t()
  def endpoint(opts \\ []) do
    opts
    |> Util.option(:asset_host, @endpoint)
    |> Util.var()
  end

  @impl Waffle.Storage.Google.Url
  def build(definition, version, meta, options) do
    path = CloudStorage.path_for(definition, version, meta)

    if signed?(options) do
      build_signed_url(definition, path, options)
    else
      build_url(definition, path)
    end
  end

  @spec build_url(Types.definition(), String.t()) :: String.t()
  defp build_url(definition, path) do
    %URI{
      host: endpoint(),
      path: build_path(definition, path),
      scheme: "https"
    }
    |> URI.to_string()
  end

  @spec build_signed_url(Types.definition(), String.t(), Keyword.t()) :: String.t()
  defp build_signed_url(definition, path, options) do
    {:ok, client_id} = Goth.Config.get(:client_email)

    expiration = System.os_time(:second) + expiry(options)

    signature =
      definition
      |> build_path(path)
      |> canonical_request(expiration)
      |> sign_request()

    base_url = build_url(definition, path)

    "#{base_url}?GoogleAccessId=#{client_id}&Expires=#{expiration}&Signature=#{signature}"
  end

  @spec build_path(Types.definition(), String.t()) :: String.t()
  defp build_path(definition, path) do
    path =
      if endpoint() != @endpoint do
        path
      else
        bucket_and_path(definition, path)
      end

    path
    |> Util.prepend_slash()
    |> URI.encode()
  end

  @spec bucket_and_path(Types.definition(), String.t()) :: String.t()
  defp bucket_and_path(definition, path) do
    definition
    |> CloudStorage.bucket()
    |> Path.join(path)
  end

  @spec canonical_request(String.t(), pos_integer) :: String.t()
  defp canonical_request(resource, expiration) do
    "GET\n\n\n#{expiration}\n#{resource}"
  end

  @spec sign_request(String.t()) :: String.t()
  defp sign_request(request) do
    {:ok, pem_bin} = Goth.Config.get("private_key")
    [pem_key_data] = :public_key.pem_decode(pem_bin)
    otp_release = System.otp_release() |> String.to_integer()

    rsa_key =
      case otp_release do
        n when n >= 21 ->
          :public_key.pem_entry_decode(pem_key_data)

        _ ->
          pem_key = :public_key.pem_entry_decode(pem_key_data)
          :public_key.der_decode(:RSAPrivateKey, elem(pem_key, 3))
      end

    request
    |> :public_key.sign(:sha256, rsa_key)
    |> Base.encode64()
    |> URI.encode_www_form()
  end
end
