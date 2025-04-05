defmodule Glific.Repo.Migrations.SkipValidation do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :skip_validation, :boolean,
      default: false,
      comment: "Allow users to skip validation for variables coming from resumeContact apis"
    end
  end
end
