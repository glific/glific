defmodule Glific.Version do
  @moduledoc """
  Schema for tracking audit history of db changes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "versions" do
    field :patch, ExAudit.Type.Patch

    field :entity_id, :integer

    field :entity_schema, ExAudit.Type.Schema

    field :action, ExAudit.Type.Action

    field :recorded_at, :utc_datetime

    field :rollback, :boolean, default: false

    belongs_to :user, Glific.Users.User
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [
      :patch,
      :entity_id,
      :entity_schema,
      :action,
      :recorded_at,
      :rollback,
      :user_id
    ])
    |> validate_required([:entity_id, :entity_schema, :action, :recorded_at])
    |> foreign_key_constraint(:user_id)
  end
end
