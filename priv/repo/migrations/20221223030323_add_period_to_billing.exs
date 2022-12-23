defmodule Glific.Repo.Migrations.AddPeriodToBilling do
  use Ecto.Migration

  def change do
    alter table(:billings) do
      add_if_not_exists(:billing_period, :string,
        comment: "stores the subscription billing period for a customer"
      )
    end
  end
end
