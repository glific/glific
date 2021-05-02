defmodule Glific.Repo.Migrations.Extensions do
  use Ecto.Migration

  def change do
    extensions()
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
end
