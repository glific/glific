defmodule GlificWeb.Resolvers.Certificate do
  @moduledoc """
  Certificate Resolver which sits between the GraphQL schema and Glific Certificate APIs.
  """
  alias Glific.Certificates.CertificateTemplate

  @doc """
  Create an Assistant
  """
  @spec create_certificate_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_certificate_template(_, %{input: params}, _) do
    CertificateTemplate.create_certificate_template(params)
  end
end
