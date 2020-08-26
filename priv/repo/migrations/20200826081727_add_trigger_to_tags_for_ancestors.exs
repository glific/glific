defmodule Glific.Repo.Migrations.AddTriggerToTagsForAncestors do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_tag_ancestors()
    RETURNS trigger AS $$
    BEGIN
      WITH RECURSIVE parents AS
      (
        SELECT id AS id, ARRAY [id] AS ancestry
        FROM tags WHERE parent_id IS NULL UNION
        SELECT child.id AS id, array_append(p.ancestry, child.id) AS ancestry
        FROM tags child INNER JOIN parents p ON p.id = child.parent_id
      )
      UPDATE tags SET ancestors = (select array_remove(parents.ancestry, tags.id) as ancestry from parents where parents.id = tags.id);

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute "DROP TRIGGER IF EXISTS update_tag_ancestors_trigger ON tags;"

    execute """
    CREATE TRIGGER update_tag_ancestors_trigger
    AFTER INSERT
    ON tags
    FOR EACH ROW
    EXECUTE PROCEDURE update_tag_ancestors();
    """
  end

  def down do
    execute "DROP FUNCTION update_tag_ancestors() CASCADE;"
  end
end
