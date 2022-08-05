defmodule Glific.Repo.Migrations.RemoveOldHistoryTrigger do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION remove_old_history() RETURNS trigger AS $$
      BEGIN
        with ranked as (SELECT id, row_number() over (partition by contact_id order by updated_at desc) as rn
           from contact_histories where id <> NEW.id and contact_id = NEW.contact_id
         )
         delete from contact_histories
         where id in (select id  from ranked where rn >= 100);

         RETURN NEW;
      END;

    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER remove_old_history_trigger
    AFTER INSERT ON contact_histories
    FOR EACH ROW EXECUTE PROCEDURE remove_old_history();
    """
  end

  def down do
    execute "DROP FUNCTION remove_old_history() CASCADE;"
  end
end
