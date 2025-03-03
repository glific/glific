defmodule GlificWeb.Resolvers.Certificate do
  @moduledoc """
  Certificate Resolver which sits between the GraphQL schema and Glific Certificate APIs.
  """
  alias Glific.{
    Certificates.Certificate,
    Certificates.CertificateTemplate,
    Repo
  }

  @doc """
  Create a certificate template
  """
  @spec create_certificate_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_certificate_template(_, %{input: params}, _) do
    Certificate.create_certificate_template(params)
  end

  @doc """
  Update a certificate template
  """
  @spec update_certificate_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_certificate_template(_, %{input: params, id: id}, %{context: %{current_user: user}}) do
    with {:ok, cert_template} <-
           Repo.fetch_by(CertificateTemplate, %{id: id, organization_id: user.organization_id}),
         # Make sure we always have type in the changest, so that we use for validating the changed url
         {:ok, cert_template} <-
           Map.put_new(params, :type, cert_template.type)
           |> then(&CertificateTemplate.update_certificate_template(cert_template, &1)) do
      {:ok, %{certificate_template: cert_template}}
    end
  end

  @doc """
  Fetches a certificate template
  """
  @spec get_certificate_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_certificate_template(_, %{id: id}, _) do
    with {:ok, cert_template} <- CertificateTemplate.get_certificate_template(id) do
      {:ok, %{certificate_template: cert_template}}
    end
  end

  @doc """
  Fetches a certificate template
  """
  @spec list_certificate_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def list_certificate_templates(_, params, _) do
    {:ok, CertificateTemplate.list_certificate_templates(params)}
  end

  @doc """
  Count of certificate templates
  """
  @spec count_certificate_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def count_certificate_templates(_, params, _) do
    {:ok, CertificateTemplate.count_certificate_templates(params)}
  end

  @spec delete_certificate_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_certificate_template(_, %{id: id}, _) do
    with {:ok, cert_template} <- Repo.fetch_by(CertificateTemplate, %{id: id}),
         {:ok, cert_template} <- CertificateTemplate.delete_certificate_template(cert_template) do
      {:ok, %{certificate_template: cert_template}}
    end
  end
end
