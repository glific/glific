defmodule Glific.Schema do
  @moduledoc """
  For glific objects (flows for now) that are using uuids as their
  primary key
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key {:uuid, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      # @derive {Phoenix.Param, key: :uuid}
    end
  end
end
