defmodule Glific.Repo.Migrations.AddProfileIdToFlowTables do
  use Ecto.Migration

  def change do
    add_profile_to_flow_results()
    add_profile_to_flow_contexts()
    add_profile_to_contact_histories()
    add_profile_to_messages()
    add_profile_id_flow_results_trigger()
    add_profile_id_flow_contexts_trigger()
    add_profile_id_contact_histories_trigger()
    add_profile_id_messages_trigger()
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

  defp add_profile_id_flow_results_trigger() do
    execute """
    CREATE OR REPLACE FUNCTION update_profile_id_on_new_flow_result()
      RETURNS trigger AS $$

      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        IF (TG_OP = 'INSERT') THEN
          UPDATE flow_results set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_profile_id_on_new_flow_result
    AFTER INSERT
    ON flow_results
    FOR EACH ROW
    EXECUTE PROCEDURE update_profile_id_on_new_flow_result();
    """
  end

  defp add_profile_id_flow_contexts_trigger() do
    execute """
    CREATE OR REPLACE FUNCTION update_profile_id_on_new_flow_context()
      RETURNS trigger AS $$

      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        IF (TG_OP = 'INSERT') THEN
          UPDATE flow_contexts set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_profile_id_on_new_flow_context
    AFTER INSERT
    ON flow_contexts
    FOR EACH ROW
    EXECUTE PROCEDURE update_profile_id_on_new_flow_context();
    """
  end

  defp add_profile_id_contact_histories_trigger() do
    execute """
    CREATE OR REPLACE FUNCTION update_profile_id_on_new_contact_history()
      RETURNS trigger AS $$

      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        IF (TG_OP = 'INSERT') THEN
          UPDATE contact_histories set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_profile_id_on_new_contact_history
    AFTER INSERT
    ON contact_histories
    FOR EACH ROW
    EXECUTE PROCEDURE update_profile_id_on_new_contact_history();
    """
  end

  defp add_profile_id_messages_trigger() do
    execute """
    CREATE OR REPLACE FUNCTION update_profile_id_on_new_message()
      RETURNS trigger AS $$

      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        IF (TG_OP = 'INSERT') THEN
          UPDATE messages set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_profile_id_on_new_message
    AFTER INSERT
    ON messages
    FOR EACH ROW
    EXECUTE PROCEDURE update_profile_id_on_new_message();
    """
  end
end
