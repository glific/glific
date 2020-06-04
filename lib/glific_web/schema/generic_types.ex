defmodule GlificWeb.Schema.GenericTypes do
  @moduledoc """
  GraphQL Representation of common data representations used across different
  Glific's DataType
  """

  use Absinthe.Schema.Notation

  @desc "An error encountered trying to persist input"
  object :input_error do
    field :key, non_null(:string)
    field :message, non_null(:string)
  end

  @desc """
  A generic status results for calls that dont return a value.
  Typically this is for delete operations
  """
  object :generic_result do
    field :status, non_null(:api_status_enum)
    field :errors, list_of(:input_error)
  end
end
