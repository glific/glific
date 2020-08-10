defmodule Glific.Repo.Migrations.UpdateProviderStatusField do
  @moduledoc """
  Update GlificTables for contact's provider status field
  """

  use Ecto.Migration

  alias Glific.Enums.ContactProviderStatus

  def up do
    ContactProviderStatus.create_type()

    update_contacts()
  end

  def down do
    ContactProviderStatus.drop_type()
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
      add :provider_status, :contact_provider_status_enum, null: false, default: "none"
    end
  end
end
