defmodule GlificWeb.Resolvers.Authentication do
  @moduledoc """
  Authentication Resolver which sits between the GraphQL schema and Glific Authentication Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Authentication

  @doc false
  @spec send_otp(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) :: {:ok, String.t()}
  def send_otp(_, %{input: params}, _) do
    with {:ok, response_message} <- Authentication.create_and_send_otp_to_phone(params),
         do: {:ok, response_message}
  end

  @doc false
  @spec verify_otp(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, String.t()}
  def verify_otp(_, %{input: params}, _) do
    with {:ok, response_message} <- Authentication.verify_otp(params),
         do: {:ok, response_message}
  end
end
