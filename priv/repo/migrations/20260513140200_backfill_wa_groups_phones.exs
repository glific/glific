defmodule Glific.Repo.Migrations.BackfillWAGroupsPhones do
  use Ecto.Migration

  # Phase 1 of the multi-phone rollout. Purely additive backfill:
  #
  # 1. One wa_groups_phones row per existing wa_group, sourced from
  #    wa_groups.wa_managed_phone_id, marked primary + active.
  # 2. wa_messages.wa_managed_phone_id populated from the joined
  #    wa_group's wa_managed_phone_id where it's still NULL.

  def up do
    execute("""
    INSERT INTO wa_groups_phones (
      wa_group_id,
      wa_managed_phone_id,
      organization_id,
      is_primary,
      is_active,
      inserted_at,
      updated_at
    )
    SELECT
      id,
      wa_managed_phone_id,
      organization_id,
      TRUE,
      TRUE,
      NOW(),
      NOW()
    FROM wa_groups
    ON CONFLICT (wa_group_id, wa_managed_phone_id) DO NOTHING
    """)

    execute("""
    UPDATE wa_messages m
    SET wa_managed_phone_id = g.wa_managed_phone_id
    FROM wa_groups g
    WHERE m.wa_group_id = g.id
      AND m.wa_managed_phone_id IS NULL
    """)
  end

  def down do
    # No-op. Backfilled rows can't be safely separated from rows created
    # post-migration, and wa_messages.wa_managed_phone_id may have been
    # populated independently by subsequent code paths. A full unwind comes
    # from rolling back the schema migration (add_wa_groups_phones), which
    # drops the table outright.
    :ok
  end
end
