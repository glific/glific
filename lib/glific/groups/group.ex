defmodule Glific.Groups.Group do
  @moduledoc """
  The minimal wrapper for the base Group structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Groups.Group,
    Partners.Organization,
    Users.User
  }

  @required_fields [:label]
  @optional_fields [:is_restricted, :description, :organization_id, :last_communication_at]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          description: String.t() | nil,
          is_restricted: boolean(),
          last_communication_at: :utc_datetime | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "groups" do
    field :label, :string
    field :description, :string
    field :is_restricted, :boolean, default: false

    field :last_communication_at, :utc_datetime

    belongs_to :organization, Organization

    many_to_many :contacts, Contact, join_through: "contacts_groups", on_replace: :delete
    many_to_many :users, User, join_through: "users_groups", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Group.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :organization_id])
  end
end
