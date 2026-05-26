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
    WHERE wa_managed_phone_id IS NOT NULL
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
    # On rollback, drop the rows we inserted. wa_messages.wa_managed_phone_id
    # cannot be safely reversed (we'd risk clearing values populated by code
    # after Phase 1), so we leave those alone.
    execute("DELETE FROM wa_groups_phones")
  end
end
