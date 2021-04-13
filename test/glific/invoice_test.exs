defmodule Glific.BillingTest do
  use Glific.DataCase
  use ExUnit.Case
  import Mock

  alias Glific.Partners.{
    Billing,
    Invoice
  }

  @current_datetime_unix DateTime.utc_now() |> DateTime.to_unix()

  @valid_attrs %{
    customer_id: "Random customer id",
    invoice_id: "Random invoice id",
    start_date: DateTime.now!("Etc/UTC"),
    end_date: DateTime.now!("Etc/UTC"),
    status: "open"
  }

  @valid_stripe_event_data %{
    stripe_invoice: %{
      customer: "Random customer id",
      id: "Random invoice id",
      status: "open",
      amount_due: "1000",
      period_start: @current_datetime_unix,
      period_end: @current_datetime_unix,
      lines: %{
        data: [
          %{
            price: %{id: "price_id", nickname: "nickname"},
            period: %{start: @current_datetime_unix, end: @current_datetime_unix}
          }
        ]
      }
    }
  }

  def billing_fixture() do
    attrs = %{
      name: "Billing name",
      email: "Billing person email",
      currency: "inr",
      stripe_subscription_id: "Stripe subscription id"
    }

    {:ok, billing} = Billing.create_billing(attrs)
    billing
  end

  test "create_invoice/1 with valid data", %{organization_id: organization_id} do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    assert {:ok, %Invoice{} = invoice} = Invoice.create_invoice(attrs)

    assert invoice.organization_id == attrs.organization_id
    assert invoice.customer_id == @valid_attrs.customer_id
    assert invoice.invoice_id == @valid_attrs.invoice_id
    assert invoice.start_date == @valid_attrs.start_date
    assert invoice.end_date == @valid_attrs.end_date
    assert invoice.status == @valid_attrs.status
  end

  test "create_invoice/1 with valid stripe event data", %{organization_id: organization_id} do
    billing_fixture()

    with_mocks([
      {
        Stripe.Subscription,
        [:passthrough],
        [update: fn _, _ -> {:ok, "Success"} end]
      }
    ]) do
      attrs = Map.merge(@valid_stripe_event_data, %{organization_id: organization_id})

      assert {:ok, %Invoice{} = invoice} = Invoice.create_invoice(attrs)

      assert invoice.organization_id == attrs.organization_id
      assert invoice.customer_id == @valid_stripe_event_data.stripe_invoice.customer
      assert invoice.invoice_id == @valid_stripe_event_data.stripe_invoice.id

      assert Timex.equal?(
               invoice.start_date,
               DateTime.from_unix!(@valid_stripe_event_data.stripe_invoice.period_start)
             )

      assert Timex.equal?(
               invoice.end_date,
               DateTime.from_unix!(@valid_stripe_event_data.stripe_invoice.period_end)
             )

      assert invoice.status == @valid_stripe_event_data.stripe_invoice.status
      assert invoice.line_items["price_id"].nickname == "nickname"
    end
  end
end
