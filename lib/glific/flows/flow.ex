defmodule Glific.Flows.Flow do
  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:name, :version_number]
  @optional_fields [:uuid, :language, :flow_type]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: String.t() | nil,
          version_number: String.t() | nil,
          language: String.t() | nil,
          flow_type: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
    }

  schema "flows" do
    field :name, :string
    field :uuid, :string
    field :version_number, :string
    field :language, :string
    field :flow_type, :string
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
