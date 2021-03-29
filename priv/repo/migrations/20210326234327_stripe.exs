defmodule Glific.Repo.Migrations.Stripe do
  use Ecto.Migration

  def change do
    billings()

    invoices()
  end

  defp billings() do
    create table(:billings) do
      # organization level info
      add :stripe_customer_id, :string
      add :stripe_payment_method_id, :string

      # subscription and price level info
      add :stripe_subscription_id, :string

      add :stripe_subscription_items, :jsonb,
        default: "{}",
        comment: "A map of stripe subscription item ids to our price and product ids"

      add :stripe_current_period_start, :utc_datetime
      add :stripe_current_period_end, :utc_datetime
      add :stripe_last_usage_recorded, :utc_datetime

      add :name, :string, comment: "Billing Contact Name, used to create the Stripe Customer"

      add :email, :string, comment: "Billing Email Address, used to create the Stripe Customer"

      add :currency, :string, comment: "Currency the account will pay bills"

      add :is_delinquent, :boolean,
        comment: "Is this account delinquent? Invoice table will have more info"

      # is this billing record active, current thinking is if the org changes currency, we
      # create a new billing record and make the old one in active
      add :is_active, :boolean,
        default: true,
        comment: "Is this the active billing record for this organization"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:billings, [:organization_id, :is_active])
    create unique_index(:billings, :stripe_customer_id)
  end

  defp invoices do
    create table(:invoices) do
      add :invoice_id, :string, null: false, unique: true, comment: "Stripe's Invoice ID"

      add :invoice_start_date, :utc_datetime_usec,
        null: false,
        comment: "The beginning date of the invoice"

      add :invoice_end_date, :utc_datetime_usec,
        null: false,
        comment: "The end date of the invoice"

      add :status, :string, null: false, comment: "The status of the invoice"
      add :amount, :integer, null: false, comment: "The amount to be paid"

      add :user_usage, :integer,
        default: 0,
        comment: "The reported number of users in the last billing cycle"

      add :message_usage, :integer,
        default: 0,
        comment: "The reported number of messages sent in the last billing cycle"

      add :consulting_hours, :integer, default: 0, comment: "The reported consulting hours"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Related organization id"

      timestamps(type: :utc_datetime)
    end
  end
end
