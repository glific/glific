defmodule Glific.Repo.Migrations.AddWaFormToMessageTypeEnum do
  use Ecto.Migration

  def up do
    execute "ALTER TYPE message_type_enum ADD VALUE 'whatsapp_form'"
  end
end
