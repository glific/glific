defmodule Glific.Repo.Migrations.AddAwaitResults do
  use Ecto.Migration

  def change do
    flow_contexts()
  end

  defp flow_contexts do
    alter table(:flow_contexts) do
      add :is_await_result, :boolean,
        default: false,
        comment: "Is this flow context waiting for a result to be delivered via an API"
    end
  end
end
