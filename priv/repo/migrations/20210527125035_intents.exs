defmodule Glific.Repo.Migrations.Intents do
  use Ecto.Migration

  def change do
    create table(:intents,
             comment: "Lets store all the intents to utilize the nlp classifiers"
           ) do
      add :name, :string, comment: "The name of the Intent (for lookup)"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        comment: "The master organization running this service"

      timestamps(type: :utc_datetime)
    end
  end
end
