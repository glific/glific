defmodule Glific.Users.User do
  @moduledoc false
  use Ecto.Schema
  use Pow.Ecto.Schema

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          email: String.t() | nil,
          password_hash: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "users" do
    pow_user_fields()

    timestamps()
  end
end
