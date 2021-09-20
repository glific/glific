defmodule Glific.Repo.Migrations.OptoutMethod do
  use Ecto.Migration

  def change do
    optout()
  end

  defp optout() do
    alter table(:contacts) do
      add :optout_method, :string,
        null: true,
        comment: "possible options include: URL, WhatsApp Message, QR Code, SMS, NGO"
    end
  end
end
