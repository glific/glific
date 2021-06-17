defmodule Glific.Repo.Migrations.Extensions do
  use Ecto.Migration

  def change do
    extensions()

    consulting_hours()
  end

  defp extensions do
    drop_if_exists table(:extensions)

    create table(:extensions, comment: "Lets store information and code for the extensions") do
      add :name, :string, comment: "The name of the extension"

      add :code, :text, comment: "The elixir source code for this module"

      add :module, :string, comment: "The name of the module, useful when we want to unload it"

      add :is_valid, :boolean, default: false, comment: "Does the code compile"

      add :is_active, :boolean, default: true

      add :organization_id, references(:organizations, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end
  end

  defp consulting_hours do
    create table(:consulting_hours, comment: "Lets track consulting hours here") do
      add :organization_id, references(:organizations, on_delete: :nilify_all)

      add :organization_name, :string,
        comment: "Record of who we billed in case we delete the organization"

      add :participants, :text, comment: "Name of NGO participants"

      add :staff, :text, comment: "Name of staff members who were on the call"

      add :when, :utc_datetime, comment: "Date and time of when the support call happened"

      add :duration, :integer, comment: "Minutes spent on call, round up to 15 minute intervals"

      add :content, :text, comment: "Agenda, and action items of the call"

      add :is_billable, :boolean, default: true, comment: "Is this call billable"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:consulting_hours, [:when, :staff, :organization_id])
    create index(:consulting_hours, :organization_id)
  end
end
