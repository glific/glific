defmodule Glific.Repo.Migrations.AddWAGroupsPhones do
  use Ecto.Migration

  def change do
    create table(:wa_groups_phones) do
      add :wa_group_id, references(:wa_groups, on_delete: :delete_all),
        null: false,
        comment: "WA group this membership belongs to"

      add :wa_managed_phone_id, references(:wa_managed_phones, on_delete: :delete_all),
        null: false,
        comment: "Maytapi-linked phone that is a member of the group"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      add :is_primary, :boolean,
        null: false,
        default: false,
        comment: "Marks the primary phone for outbound sends to this group"

      add :is_active, :boolean,
        null: false,
        default: true,
        comment: "False when the phone is no longer a member of the group on WhatsApp"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:wa_groups_phones, [:wa_group_id, :wa_managed_phone_id])

    create unique_index(:wa_groups_phones, [:wa_group_id],
             where: "is_primary IS TRUE",
             name: :wa_groups_phones_one_primary
           )

    create index(:wa_groups_phones, [:organization_id])
  end
end
