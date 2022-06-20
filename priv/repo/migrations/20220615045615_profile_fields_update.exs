defmodule Glific.Repo.Migrations.ProfileFieldsUpdate do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      remove :profile_registration_fields, :map
      remove :contact_profile_fields, :map

      add :fields, :map,
        comment:
          "Labels and values of the NGO generated fields for the contact which is synced in/out to contact fields"
    end
  end
end
