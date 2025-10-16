defmodule Glific.Version do
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
    |> cast(params, [:patch, :entity_id, :entity_schema, :action, :recorded_at, :rollback])
    |> cast(params, [:user_id])
  end
end
