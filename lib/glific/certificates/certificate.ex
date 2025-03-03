defmodule Glific.Certificates.Certificate do
  @moduledoc """
  Functions related to certificate templates and managing issued certificates
  """
  alias Glific.Certificates.CertificateTemplate

  @slides_url_prefix "https://docs.google.com/presentation/"

  # TODO: doc
  @spec create_certificate_template(map()) :: {:ok, map()} | {:error, any()}
  def create_certificate_template(params) do
    # Internally we have `type` of url, although we only support slides now
    params = Map.put_new(params, :type, "slides")

    with :ok <- validate_url(params.url, params.type),
         {:ok, cert_template} <- CertificateTemplate.create_certificate_template(params) do
      {:ok, %{certificate_template: cert_template}}
    end
  end

  @spec validate_url(String.t(), String.t()) :: :ok | {:error, String.t()}
  defp validate_url(url, type) do
    with :ok <- Glific.URI.cast(url),
         :ok <- validate_by_type(url, type),
         {:ok, %Tesla.Env{status: status}} when status in 200..299 <-
           Tesla.get(url, opts: [adapter: [recv_timeout: 10_000]]) do
      :ok
    else
      {:error, _type, reason} ->
        {:error, reason}

      _ ->
        {:error, "Invalid Template url"}
    end
  end

  @spec validate_by_type(String.t(), String.t()) :: :ok | {:error, String.t(), String.t()}
  defp validate_by_type(url, "slides") do
    if String.starts_with?(url, @slides_url_prefix) do
      :ok
    else
      {:error, "slides", "Template url not a valid Google Slides"}
    end
  end

  defp validate_by_type(_url, type), do: {:error, type, "Template of type #{type} not supported yet"}
end
