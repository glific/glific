defmodule Glific.Repo.Migrations.V04AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.4 Alter Glific tables
  """

  def up do
    alter table(:flows) do
      # Removing shortcode, keywords can be used if required
      remove :shortcode
    end
  end
end
