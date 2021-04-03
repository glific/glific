defmodule StripeController do
  @moduledoc """
  The controller for all events received from Stripe
  """

  use GlificWeb, :controller

  alias Glific.Partners.Invoice

  @doc """
  The top level API used by the router. Use pattern matching to handle specific events
  """
  @spec stripe_webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stripe_webhook(
        %Plug.Conn{assigns: %{stripe_event: stripe_event, organization_id: organization_id}} =
          conn,
        _params
      ) do
    case handle_webhook(stripe_event, organization_id) do
      {:ok, _} -> handle_success(conn)
      {:error, error} -> handle_error(conn, error)
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
    %{type: "invoice.upcoming", data: %{object: invoice}} = _stripe_event,
    organization_id
  ),
  do: Invoice.update_usage(invoice, organization_id)

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

  defp handle_webhook(stripe_event, _organization_id) do
    # handle default case. We ignore these web hooks.
    {:ok, "success, ignoring #{stripe_event.type}"}
  end
end
