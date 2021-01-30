defmodule Glific.Repo.Migrations.UpgradeV10 do
  use Ecto.Migration

  def change do
    messages()
  end

  defp messages do
    create unique_index(:messages, :bsp_message_id)
  end
end
