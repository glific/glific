defmodule Glific.Version do
  @moduledoc """
  Schema for tracking audit history of db changes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          patch: map() | nil,
          entity_id: integer() | nil,
          entity_schema: String.t() | nil,
          action: String.t() | nil,
          recorded_at: DateTime.t() | nil,
          rollback: boolean(),
          user_id: integer() | nil,
          organization_id: integer() | nil,
          user: Glific.Users.User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization: Glific.Partners.Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "versions" do
    field :patch, ExAudit.Type.Patch
    field :entity_id, :integer
    field :entity_schema, ExAudit.Type.Schema
    field :action, ExAudit.Type.Action
    field :recorded_at, :utc_datetime
    field :rollback, :boolean, default: false

    belongs_to :user, Glific.Users.User
    belongs_to :organization, Glific.Partners.Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Version.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [
      :patch,
      :entity_id,
      :entity_schema,
      :action,
      :recorded_at,
      :rollback,
      :user_id,
      :organization_id
    ])
    |> validate_required([:entity_id, :entity_schema, :action, :recorded_at])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
