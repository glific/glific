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
    attrs = %{
      invoice_id: invoice.id,
      organization_id: organization_id,
      status: invoice.status,
      amount: invoice.amount_due,
      invoice_start_date: DateTime.from_unix!(invoice.period_start),
      invoice_end_date: DateTime.from_unix!(invoice.period_end)
    }

    line_items =
      invoice.lines.data
      |> Enum.reduce(%{}, fn line, acc -> Map.put(acc, line.price.id, line.price.nickname) end)

    attrs = Map.put(attrs, :line_items, line_items)

    case Invoice.create_invoice(attrs) do
      {:ok, invoice} -> {:ok, "success, #{invoice.id}"}
      {:error, error} -> {:error, error}
    end
  end

  defp handle_webhook(
         %{type: "invoice.payment_succeeded", data: %{object: invoice}} = _stripe_event,
         _organization_id
       ) do
    invoice = Invoice.fetch_invoice!(invoice.id)

    case Invoice.update_invoice(invoice, %{status: "paid"}) do
      {:ok, invoice} -> {:ok, "success, #{invoice.id}"}
      {:error, error} -> {:error, error}
    end
  end

  defp handle_webhook(
         %{type: "invoice.payment_failed", data: %{object: invoice}} = _stripe_event,
         _organization_id
       ) do
    invoice = Invoice.fetch_invoice!(invoice.id)

    case Invoice.update_invoice(invoice, %{status: "failed"}) do
      {:ok, invoice} -> {:ok, "success, #{invoice.id}"}
      {:error, error} -> {:error, error}
    end
  end

  defp handle_webhook(stripe_event, _organization_id) do
    # handle default case. We ignore these web hooks.
    {:ok, "success, #{inspect(stripe_event)}"}
  end
end
