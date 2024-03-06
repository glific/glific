defmodule Glific.Groups.WAGroupsCollection do
  @moduledoc """
  A pipe for managing the contact whatsapp groups
  """

  alias Glific.{
    Groups.Group,
    Groups.WAGroup,
    Groups.WAGroupsCollection,
    Partners.Organization
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:group_id, :wa_group_id, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil,
          wa_group: WAGroup.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "wa_groups_collections" do
    field :is_admin, :boolean, default: false
    belongs_to :group, Group
    belongs_to :wa_group, WAGroup
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WAGroupsCollection.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:group_id, :wa_group_id])
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:wa_group_id)
  end
end
