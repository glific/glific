defmodule GlificWeb.Resolvers.Certificate do
  @moduledoc """
  Certificate Resolver which sits between the GraphQL schema and Glific Certificate APIs.
  """
  alias Glific.Certificates.Certificate

  @doc """
  Create a certificate template
  """
  @spec create_certificate_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_certificate_template(_, %{input: params}, _) do
    Certificate.create_certificate_template(params)
  end
end
