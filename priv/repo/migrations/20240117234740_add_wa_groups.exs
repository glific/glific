  defmodule Glific.Repo.Migrations.AddWAGroups do
    use Ecto.Migration

    @global_schema Application.compile_env!(:glific, :global_schema)

    def change do
      wa_managed_phones()

      messages()

      contacts()

      groups()
    end

    defp wa_managed_phones do
      create table(:wa_managed_phones) do
        add :label, :string, null: false, comment: "Identification for this phone"

        # phone number that we are using for external api
        add :phone, :string, null: false

        # other ids that that provider uses in the url (maytapi)
        add :phone_id, :string
        add :product_id, :string

        add :is_active, :boolean,
          default: true,
          comment: "Whether the phone number is currently active"

        # we will keep the token encrypted
        add :api_token, :binary

        # foreign key to provider, so we know the relevant apis to call to send/receive messages
        add :provider_id, references(:providers, on_delete: :delete_all, prefix: @global_schema), null: false

        # foreign key to organization restricting scope of this table to this organization only
        add :organization_id, references(:organizations, on_delete: :delete_all), null: false

        timestamps(type: :utc_datetime_usec)
      end

      create unique_index(:wa_managed_phones, :organization_id)
      create unique_index(:wa_managed_phones, :phone)
    end

    defp messages do
      alter table(:messages) do
        add :message_type, :string, comment: "one of WABA, WA"
      end
    end

    defp contacts do
      alter table(:contacts) do
        add :contact_type, :string, comment: "one of WABA, WA, WABA+WA"
      end
    end

    defp groups do
      alter table(:groups) do
        add :group_type, :string, comment: "one of WABA or WA (cannot be both)"
      end
    end
  end
