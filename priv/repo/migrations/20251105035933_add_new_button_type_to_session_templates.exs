defmodule Glific.Repo.Migrations.AddNewButtonTypeToSessionTemplates do
  use Ecto.Migration

  def up do
    execute("ALTER TYPE template_button_type_enum ADD VALUE IF NOT EXISTS 'whatsapp_form'")
  end

  def down do
    execute("""
    CREATE TYPE template_button_type_enum_new AS ENUM ('call_to_action', 'quick_reply', 'otp');
    """)

    execute("""
    ALTER TABLE session_templates
    ALTER COLUMN button_type TYPE template_button_type_enum_new
    USING button_type::text::template_button_type_enum_new;
    """)

    execute("DROP TYPE template_button_type_enum;")
    execute("ALTER TYPE template_button_type_enum_new RENAME TO template_button_type_enum;")
  end
end
