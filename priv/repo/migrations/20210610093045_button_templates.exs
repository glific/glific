defmodule Glific.Repo.Migrations.ButtonTemplates do
  use Ecto.Migration

  alias Glific.Enums.TemplateButtonType

  def up do
    TemplateButtonType.create_type()
    add_button_session_templates()
  end

  def down do
    TemplateButtonType.drop_type()
  end

  defp add_button_session_templates() do
    alter table(:session_templates) do
      add :has_buttons, :boolean,
        default: false,
        comment: "Does template have buttons"

      add :button_type, :template_button_type_enum,
        comment: "type of button QUICK_REPLY or CALL_TO_ACTION"

      add :buttons, :jsonb, default: "[]"
    end
  end
end
