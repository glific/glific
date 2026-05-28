defmodule Glific.Repo.Migrations.AddWAManagedPhoneIdToWAMessages do
  use Ecto.Migration

  # The wa_messages.wa_managed_phone_id column + FK were added in
  # 20240117234740_add_wa_groups.exs but no index was created. Outbound
  # lookups and the upcoming Phase 3 inbound stamping both query by
  # wa_managed_phone_id, so the index is required.
  def change do
    create_if_not_exists index(:wa_messages, [:wa_managed_phone_id])
  end
end
