defmodule Glific.Repo.Migrations.AddNewButtonTypeToSessionTemplates do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE template_button_type_enum ADD VALUE IF NOT EXISTS 'whatsapp_form'")
  end
end
