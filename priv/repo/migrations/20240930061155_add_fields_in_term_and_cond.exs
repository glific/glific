defmodule Glific.Repo.Migrations.AddFieldsInTermAndCond do
  use Ecto.Migration

  def change do
    alter table(:registrations) do
      add :is_disputed, :boolean,
        null: true,
        comment: "if the user disputed the T&C"
    end
  end
end
