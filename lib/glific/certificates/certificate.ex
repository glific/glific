defmodule Glific.Certificates.Certificate do
  @moduledoc """
  Functions related to certificate templates and managing issued certificates
  """
  alias Glific.Certificates.CertificateTemplate

  @doc """
  Creates a certificate template
  """
  @spec create_certificate_template(map()) :: {:ok, map()} | {:error, any()}
  def create_certificate_template(params) do
    # Internally we have `type` of url, although we only support slides now
    params = Map.put_new(params, :type, :slides)

    with {:ok, cert_template} <- CertificateTemplate.create_certificate_template(params) do
      {:ok, %{certificate_template: cert_template}}
    end
  end
end
