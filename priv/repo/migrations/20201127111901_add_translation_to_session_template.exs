defmodule Glific.Repo.Migrations.AddTranslationToSessionTemplate do
  @moduledoc """
  Adding translation to session template table
  """
  use Ecto.Migration

  def change do
    translations()
  end

  def translations() do
    alter table(:session_templates) do
      add :translations, {:array, :map}, default: []
    end
  end

end
