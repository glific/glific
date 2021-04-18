defmodule Glific.Repo.Migrations.AddObanProducers do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    Oban.Pro.Migrations.Producers.change(prefix: @global_schema)
  end
end
