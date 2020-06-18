defmodule GlificWeb.Schema.AuthenticationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Authentication
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  input_object :authentication_input do
    field :name, :string
    field :phone, :string
    field :password, :string
  end

  input_object :verification_input do
    field :phone, :string
    field :otp, :string
  end

  object :authentication_mutations do
    field :send_otp, :string do
      arg(:input, non_null(:authentication_input))
      resolve(&Resolvers.Authentication.send_otp/3)
    end

    field :verify_otp, :string do
      arg(:input, non_null(:verification_input))
      resolve(&Resolvers.Authentication.verify_otp/3)
    end
  end
end
