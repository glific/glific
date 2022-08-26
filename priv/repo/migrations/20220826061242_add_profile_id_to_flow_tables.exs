defmodule Glific.Repo.Migrations.AddProfileIdToFlowTables do
  use Ecto.Migration

  def change do
    add_profile_to_flow_results()
    add_profile_to_flow_contexts()
    add_profile_to_contact_histories()
    add_profile_to_messages()
  end

  defp add_profile_to_flow_results() do
    alter table(:flow_results) do
      add :profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end

  defp add_profile_to_flow_contexts() do
    alter table(:flow_contexts) do
      add :profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end

  defp add_profile_to_contact_histories() do
    alter table(:contact_histories) do
      add :profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end

  defp add_profile_to_messages() do
    alter table(:messages) do
      add :profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end
end
