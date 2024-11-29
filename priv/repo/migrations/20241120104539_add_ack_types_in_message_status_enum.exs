defmodule Glific.Repo.Migrations.AddAckTypesInMessageStatusEnum do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE message_status_enum ADD VALUE 'reached'")
    execute("ALTER TYPE message_status_enum ADD VALUE 'seen'")
    execute("ALTER TYPE message_status_enum ADD VALUE 'played'")
    execute("ALTER TYPE message_status_enum ADD VALUE 'deleted'")
  end
end
