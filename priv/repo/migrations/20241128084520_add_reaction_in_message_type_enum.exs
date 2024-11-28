defmodule Glific.Repo.Migrations.AddReactionInMessageTypeEnum do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE message_type_enum ADD VALUE 'reaction'")
  end
end
