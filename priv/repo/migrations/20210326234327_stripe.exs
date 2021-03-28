defmodule Glific.Repo.Migrations.Stripe do
  use Ecto.Migration

  def change do
    organizations()

    invoices()
  end

  defp organizations() do
    alter table(:organizations) do
      add :stripe_customer_id, :string
      add :stripe_payment_method_id, :string
      add :stripe_subscription_id, :string
      add :stripe_current_period_start, :utc_datetime
      add :stripe_current_period_end, :utc_datetime
      add :stripe_last_usage_recorded, :utc_datetime

      add :billing_name, :string,
        comment: "Billing Contact Name, used to create the Stripe Customer"

      add :billing_email, :string,
        comment: "Billing Email Address, used to create the Stripe Customer"

      add :billing_currency, :string, comment: "Currency the account will pay bills"

      add :is_delinquent, :boolean,
        comment: "Is this account delinquent? Invoice table will have more info"
    end

    create unique_index(:organizations, :stripe_customer_id)
  end

  # add the invoice table here
  defp invoices do
  end
end
