defmodule GlificWeb.StripeWebhook do
  @moduledoc """
  Simple plug to handle and authenticate incoming webhook calls from Stripe
  """

  @behaviour Plug

  alias Plug.Conn

  @doc false
  def init(config), do: config

  @doc false
  def call(%{request_path: "/webhook/stripe"} = conn, _) do
    signing_secret = Application.fetch_env!(:stripity_stripe, :signing_secret)
    [stripe_signature] = Conn.get_req_header(conn, "stripe-signature") |> IO.inspect(label: "Signature")

    with {:ok, body, _} <- Conn.read_body(conn),
         {:ok, stripe_event} <-
    Stripe.Webhook.construct_event(body, stripe_signature, signing_secret) do
      IO.inspect(stripe_event.type, label: "EVENT")
      conn |> Plug.Conn.assign(:stripe_event, stripe_event)
    else
      {:error, error} ->
        conn
        |> Conn.send_resp(:bad_request, inspect(error))
        |> Conn.halt()
    end
  end

  @doc false
  def call(conn, _), do: conn
end
