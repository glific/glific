defmodule GlificWeb.Schema.RegistrationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Registration
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  input_object :registration_input do
    field :name, :string
    field :phone, :string
    field :password, :string
  end

  object :registration_mutations do
    field :send_otp, :string do
      arg(:input, non_null(:registration_input))
      resolve(&Resolvers.Registration.send_otp/3)
    end
  end
end
