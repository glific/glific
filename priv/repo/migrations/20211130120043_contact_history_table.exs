defmodule Glific.Repo.Migrations.ContactHistoryTable do
  use Ecto.Migration

  def change do
    contact_histories()
  end

  defp contact_histories() do
    create table(:contact_histories,
             comment: "This table will hold all the contact history for a contact."
           ) do
      add(:contact_id, references(:contacts, on_delete: :delete_all), null: false)
      add(:event_type, :string, comment: "The type of event that happened.")
      add(:event_label, :string, comment: "The name of the event.")
      add(:event_meta, :map, default: %{}, comment: "The meta data for the event that happened.")

      add(:event_datetime, :utc_datetime, comment: "The date and time of the event that happened.")

      add(:organization_id, references(:organizations, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end
  end
end
