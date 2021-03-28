defmodule StripeController do
  @moduledoc """
  The controller for all events received from Stripe
  """

  use GlificWeb, :controller

  @doc """
  The top level API used by the router. Use pattern matching to handle specific events
  """
  @spec stripe_webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stripe_webhook(%Plug.Conn{assigns: %{stripe_event: stripe_event}} = conn, _params) do
    case handle_webhook(stripe_event) do
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

  @spec handle_webhook(map()) :: {:ok | :error, String.t()}
  defp handle_webhook(%{type: "invoice.created"} = stripe_event) do
    # handle invoice created webhook
    {:ok, "success, #{stripe_event}"}
  end

  defp handle_webhook(%{type: "invoice.payment_succeeded"} = stripe_event) do
    # handle invoice payment_succeeded webhook
    {:ok, "success, #{stripe_event}"}
  end

  defp handle_webhook(%{type: "invoice.payment_failed"} = stripe_event) do
    # handle invoice payment_failed webhook
    {:error, "success, #{stripe_event}"}
  end
end
