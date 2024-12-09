defmodule Glific.Repo.Migrations.AddStatusTypePollInMsgTypeEnum do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE message_type_enum ADD VALUE 'poll'")
  end
end
