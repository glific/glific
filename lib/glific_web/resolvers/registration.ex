defmodule GlificWeb.Resolvers.Registration do
  @moduledoc """
  Registration Resolver which sits between the GraphQL schema. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Registration

  @doc false
  @spec send_otp(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) :: {:ok, String.t()}
  def send_otp(_, %{input: params}, _) do
    %{phone: phone} = params

    with {:ok, otp} <- PasswordlessAuth.create_and_send_verification_code(phone),
         do: {:ok, "OTP #{otp} sent successfully to #{phone}"}
  end
end
