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

    rename table("organizations"), :provider_key, to: :provider_appname

    alter table(:organizations) do
      # add a provider limit field to limit rate of messages / minute
      add :provider_limit, :integer, default: 60
    end

    alter table(:providers) do
      # add the handler and worker fields
      add :handler, :string, null: false
      add :worker, :string, null: false
    end
  end
end
