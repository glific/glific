defmodule Glific.Repo.Migrations.AddSheetType do
  use Ecto.Migration

  def change do
    add_sheet_type()
  end

  defp add_sheet_type() do
    alter table(:sheets) do
      add(:type, :string,
        comment: "Google sheet type which can be READ, WRITE or ALL"
      )
    end
  end
end
