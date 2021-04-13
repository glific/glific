defmodule StripeController do
  @moduledoc """
  The controller for all events received from Stripe
  """

  use GlificWeb, :controller

  alias Glific.Partners.{
    Billing,
    Invoice
  }

  alias Glific.Repo
  require Logger

  @doc """
  The top level API used by the router. Use pattern matching to handle specific events
  """
  @spec stripe_webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stripe_webhook(
        %Plug.Conn{assigns: %{stripe_event: stripe_event, organization_id: organization_id}} =
          conn,
        _params
      ) do

    organization_id = get_organization_id(stripe_event) || organization_id

    Logger.info("Stripe webhook called with event #{stripe_event.type} and organization_id #{organization_id}")
    case handle_webhook(stripe_event, organization_id) do
      {:ok, _} -> handle_success(conn)
      {:error, error} -> handle_error(conn, error)
    end
  end

  ## We might need to move this to stripe webhook plug.
  ## I am just not sure that how it will impact on other request and if the
  ## customer id is present in all endpoints.
  @spec get_organization_id(any()) :: integer()
  defp get_organization_id(stripe_event) do
    object = stripe_event.object
    with true <- is_struct(stripe_event.object),
    {:ok, billing} <- Repo.fetch_by(Billing, %{stripe_customer_id: object.customer}, skip_organization_id: true)
    do
      Repo.put_process_state(billing.organization_id)
      billing.organization_id
    else
      _ -> nil
    end
  end

  @spec handle_success(Plug.Conn.t()) :: Plug.Conn.t()
  defp handle_success(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end

  @spec handle_error(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp handle_error(conn, error) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(422, error)
  end

  @spec handle_webhook(map(), non_neg_integer) :: {:ok | :error, String.t()}
  defp handle_webhook(
         %{type: "invoice.created", data: %{object: invoice}} = _stripe_event,
         organization_id
       ) do
    case Invoice.create_invoice(%{stripe_invoice: invoice, organization_id: organization_id}) do
      {:ok, invoice} -> {:ok, "success, #{invoice.id}"}
      {:error, error} -> {:error, inspect(error)}
    end
  end

  defp handle_webhook(
         %{type: "invoice.payment_succeeded", data: %{object: invoice}} = _stripe_event,
         _organization_id
       ),
       do: Invoice.update_invoice_status(invoice.id, "paid")

  defp handle_webhook(
         %{type: "invoice.payment_failed", data: %{object: invoice}} = _stripe_event,
         _organization_id
       ),
       do: Invoice.update_invoice_status(invoice.id, "payment_failed")

  defp handle_webhook(
         %{type: "customer.subscription.updated", data: %{object: subscription}} = _stripe_event,
         organization_id
       ),
       do: Billing.update_subscription_details(subscription, organization_id, nil)

  defp handle_webhook(stripe_event, _organization_id) do
    # handle default case. We ignore these web hooks.
    {:ok, "success, ignoring #{stripe_event.type}"}
  end
end
