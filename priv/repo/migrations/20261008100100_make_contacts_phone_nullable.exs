defmodule Glific.Repo.Migrations.MakeContactsPhoneNullable do
  @moduledoc """
  A contact who only logs in with a username has no phone. Dropping NOT NULL is a catalog-only
  change (no rewrite, no scan), and the `(phone, organization_id)` unique index stays as it is:
  NULLs never collide, and `Contacts.upsert/1` and `BulkImport` rely on it as their conflict target.
  """
  use Ecto.Migration

  def up do
    # The ALTER needs a brief ACCESS EXCLUSIVE lock; fail fast rather than queue behind a long query.
    execute("SET LOCAL lock_timeout = '5s'")
    execute("ALTER TABLE contacts ALTER COLUMN phone DROP NOT NULL")
  end

  def down do
    # Fails while any phone-less contact exists, on purpose: rolling back would orphan them.
    execute("ALTER TABLE contacts ALTER COLUMN phone SET NOT NULL")
  end
end
