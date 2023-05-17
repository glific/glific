defmodule Glific.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      add(:body, :string)
      add(:topic, :string)

      add(:status, :string, comment: "Status of this ticket: Open or Closed")
      add(:remarks, :string, comment: "Closing remarks for the ticket")

      # contact who initiated this ticket
      add(:contact_id, references(:contacts, on_delete: :delete_all), null: false)

      # user to whom the ticket is assigned
      add(:user_id, references(:users, on_delete: :nilify_all), null: true)

      # foreign key to organization restricting scope of this table to this organization only
      add(:organization_id, references(:organizations, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:tickets, :organization_id))
  end
end
