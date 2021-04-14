defmodule Glific.InvoiceTest do
  use Glific.DataCase
  use ExUnit.Case
  import Mock

  alias Glific.{
    Fixtures,
    Partners.Billing,
    Partners.Invoice
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
      id: "Random invoice id 2",
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

  @valid_stripe_event_data_with_setup %{
    stripe_invoice: %{
      customer: "Random customer id",
      id: "Random invoice id 2",
      status: "open",
      amount_due: "1000",
      period_start: @current_datetime_unix,
      period_end: @current_datetime_unix,
      lines: %{
        data: [
          %{
            price: %{id: "price_id", nickname: "nickname"},
            period: %{start: @current_datetime_unix, end: @current_datetime_unix}
          },
          %{
            price: %{id: "price_id_2", nickname: "setup"},
            period: %{start: @current_datetime_unix, end: @current_datetime_unix}
          }
        ]
      }
    }
  }

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

  test "create_invoice/1 with valid stripe event data creates invoice when not present", %{
    organization_id: organization_id
  } do
    Fixtures.billing_fixture(%{organization_id: organization_id})

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

  test "create_invoice/1 with valid stripe event data updates invoice status if invoice allready present",
       %{
         organization_id: organization_id
       } do
    Fixtures.billing_fixture(%{organization_id: organization_id})

    with_mocks([
      {
        Stripe.Subscription,
        [:passthrough],
        [update: fn _, _ -> {:ok, "Success"} end]
      }
    ]) do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})
      {:ok, invoice} = Invoice.create_invoice(attrs)

      stripe_invoice_data =
        Map.merge(@valid_stripe_event_data.stripe_invoice, %{
          status: "paid",
          id: invoice.invoice_id
        })

      attrs =
        Map.merge(@valid_stripe_event_data, %{
          organization_id: organization_id,
          stripe_invoice: stripe_invoice_data
        })

      {:ok, result} = Invoice.create_invoice(attrs)

      assert result.id == invoice.id
      assert result.status == "paid"
    end
  end

  test "create_invoice/1 with valid stripe event data finalizes setup invoice",
       %{
         organization_id: organization_id
       } do
    Fixtures.billing_fixture(%{organization_id: organization_id})

    with_mocks([
      {
        Stripe.Subscription,
        [:passthrough],
        [update: fn _, _ -> {:ok, "Success"} end]
      },
      {
        Stripe.Invoice,
        [:passthrough],
        [finalize: fn _, _ -> {:ok, "Success"} end]
      }
    ]) do
      attrs =
        Map.merge(@valid_stripe_event_data_with_setup, %{
          organization_id: organization_id
        })

      {:ok, result} = Invoice.create_invoice(attrs)

      assert called(Stripe.Invoice.finalize(result.invoice_id, %{}))
    end
  end

  test "create_invoice/1 with valid stripe event data enables prorations",
       %{
         organization_id: organization_id
       } do
    billing = Fixtures.billing_fixture(%{organization_id: organization_id})

    with_mocks([
      {
        Stripe.Subscription,
        [:passthrough],
        [update: fn _, _ -> {:ok, "Success"} end]
      }
    ]) do
      attrs =
        Map.merge(@valid_stripe_event_data, %{
          organization_id: organization_id
        })

      Invoice.create_invoice(attrs)

      assert called(Stripe.Subscription.update(billing.stripe_subscription_id, %{prorate: true}))
    end
  end

  test "fetch_invoice/1 fetches the invoice ", %{organization_id: organization_id} do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})
    {:ok, invoice} = Invoice.create_invoice(attrs)

    result = Invoice.fetch_invoice(%{invoice_id: invoice.invoice_id})

    assert result == invoice
  end

  test "update_invoice/1 updates the invoice ", %{organization_id: organization_id} do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})
    {:ok, invoice} = Invoice.create_invoice(attrs)

    result = Invoice.update_invoice(invoice, %{status: "closed"})

    assert result.id == invoice.id
    assert result.status == "closed"
  end

  test "count_invoices/1 returns invoice counts based on the filter args ", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    result = Invoice.count_invoices(%{filter: %{organization_id: organization_id}})
    assert result == 0

    {:ok, invoice} = Invoice.create_invoice(attrs)

    result =
      Invoice.count_invoices(%{
        filter: %{status: invoice.status, organization_id: invoice.organization_id}
      })

    assert result == 1
  end

  test "update_invoice_status/1 updates invoice status and delinquency", %{
    organization_id: organization_id
  } do
    billing = Fixtures.billing_fixture(%{organization_id: organization_id})
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})
    {:ok, invoice} = Invoice.create_invoice(attrs)

    assert {:ok, "Invoice status updated for #{invoice.invoice_id}"} ==
             Invoice.update_invoice_status(invoice.invoice_id, "paid")

    assert Invoice.fetch_invoice(%{invoice_id: invoice.invoice_id}).status == "paid"

    # Ensure delinquency is true if status updated to the payment_failed
    assert {:ok, "Invoice status updated for #{invoice.invoice_id}"} ==
             Invoice.update_invoice_status(invoice.invoice_id, "payment_failed")

    assert Invoice.fetch_invoice(%{invoice_id: invoice.invoice_id}).status == "payment_failed"
    assert Billing.get_billing(%{id: billing.id}).is_delinquent == true

    # Ensure delinquency is true if any invoice exists with status as payment_failed
    attrs = Map.merge(attrs, %{invoice_id: "random", status: "payment_failed"})
    Invoice.create_invoice(attrs)

    assert {:ok, "Invoice status updated for #{invoice.invoice_id}"} ==
             Invoice.update_invoice_status(invoice.invoice_id, "paid")

    assert Invoice.fetch_invoice(%{invoice_id: invoice.invoice_id}).status == "paid"
    assert Billing.get_billing(%{id: billing.id}).is_delinquent == true
  end
end
