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

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          poll_content: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "wa_polls" do
    field :label, :string
    field :poll_content, :map, default: %{}

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WaPoll.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_poll, attrs) do
    wa_poll
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :organisation_id],
      name: :wa_poll_label_organization_id_index
    )
    |> foreign_key_constraint(:organization_id)
  end
end
