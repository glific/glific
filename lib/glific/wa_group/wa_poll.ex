defmodule Glific.WaGroup.WaPoll do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.Partners.Organization

  @required_fields [
    :label,
    :poll_content,
    :organization_id
  ]

  @optional_fields [
    :allow_multiple_answer
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          label: String.t() | nil,
          poll_content: map() | nil,
          allow_multiple_answer: boolean(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "wa_polls" do
    field :uuid, Ecto.UUID, autogenerate: true
    field :label, :string
    field :poll_content, :map, default: %{}
    field :allow_multiple_answer, :boolean, default: false

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WaPoll.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_poll, attrs) do
    wa_poll
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :organization_id])
    |> foreign_key_constraint(:organization_id)
  end
end
