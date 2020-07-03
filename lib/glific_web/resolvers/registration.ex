defmodule GlificWeb.Resolvers.Registration do
  @moduledoc """
  Registration Resolver which sits between the GraphQL schema. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  @doc false
  @spec send_otp(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) :: {:ok, String.t()}
  def send_otp(_, %{input: params}, _) do
    %{phone: phone} = params

    with {:ok, contact} <- Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone}),
         true <- Glific.Contacts.can_send_message_to?(contact),
         {:ok, otp} <- PasswordlessAuth.create_and_send_verification_code(phone) do
      {:ok, "OTP #{otp} sent successfully to #{phone}"}
    else
      {:error, _} ->
        {:ok, "Phone number is incorrect"}

      false ->
        {:ok, "Contact is not opted in yet"}
    end
  end
end
