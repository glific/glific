defmodule Glific.Repo.Migrations.ButtonTemplates do
  use Ecto.Migration

  alias Glific.Enums.TemplateButtonType

  def up do
    add_button_session_templates()
    TemplateButtonType.create_type()
  end

  def down do
    TemplateButtonType.drop_type()
  end

  defp add_button_session_templates() do
    alter table(:session_templates) do
      add :has_buttons, :boolean,
        default: false,
        comment: "Does template have buttons"

      add :button_type, :string,
        default: "",
        comment: "type of button QUICK_REPLY or CALL_TO_ACTION"

      add :buttons, :map, default: %{}, comment: "JSON object for storing buttons"
    end
  end
end
