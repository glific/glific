defmodule Glific.Repo.Migrations.AddStripeTaxRates do
  use Ecto.Migration

  def change do
    stripe_tax()
  end

  defp stripe_tax do
    alter table(:saas) do
      add :tax_rates, :jsonb,
        default: "[]",
        comment: "All the stripe tax rates"
    end
  end
end
