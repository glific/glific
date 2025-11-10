defmodule Glific.Repo.Migrations.AddWaFormToMessageTypeEnum do
  use Ecto.Migration

  def up do
    execute "ALTER TYPE message_type_enum ADD VALUE 'wa_form'"
  end

  def down do
    # Note: PostgreSQL doesn't support removing enum values
    # You would need to recreate the enum type to remove a value
    raise "Cannot remove enum value"
  end
end
