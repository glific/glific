defmodule Glific.Repo.Migrations.CreateMailLogTable do
  use Ecto.Migration

  def change do
    mail_logs()
  end

  @doc """
  Create flow label to associate flow messages with label
  """
  def mail_logs do
    create table(:mail_logs) do
      add(:category, :string, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:error, :string)
      add(:content, :map, default: %{})

      # foreign key to organization restricting scope of this table to this organization only
      add(:organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"
      )

      timestamps(type: :utc_datetime)
    end
  end
end
