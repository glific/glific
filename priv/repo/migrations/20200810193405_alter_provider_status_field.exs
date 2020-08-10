defmodule Glific.Repo.Migrations.UpdateProviderStatusField do
  @moduledoc """
  Update GlificTables for contact's provider status field
  We can remove this file, after running the migration and migrating the data in the production once
  """

  use Ecto.Migration

  alias Glific.Enums.ContactProviderStatus

  def change do
    ContactProviderStatus.create_type()

    update_contacts()
  end

  @doc """
    alter provider satatus column in contact's table
  """
  def update_contacts do
    alter table(:contacts) do
      # remove existing column of provider status with valid default value
      remove :provider_status

      # whatsapp status
      # the current options are: none, session, session_and_hsm, hsm.
      add :provider_status, :contact_provider_status_enum, null: false, default: "none", after: :status
    end
  end
end
