defmodule Glific.Repo.Migrations.AddOtpToButtonTypes do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      modify :button_type, :string
    end
  end
end
