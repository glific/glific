defmodule Glific.Repo.Migrations.BackgroundFlows do
  use Ecto.Migration

  def change do
    flows()
  end

  defp flows do
    alter table(:flows) do
      add :is_background, :boolean,
        default: false,
        comment: "Whether flows are background flows or not"
    end

    rename table(:flow_contexts), :wait_for_time, to: :is_background_flow
  end
end
