defmodule Glific.Providers.Stripe do
  @moduledoc """
  Http API client to interact with Stripe
  """
  alias Plug.Conn.Query
  use Tesla

  plug Tesla.Middleware.Headers, [
    {"Authorization", "Bearer #{Application.fetch_env!(:stripity_stripe, :api_key)}"}
  ]

  plug Tesla.Middleware.Logger

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

  @doc """
  Making Tesla post call and adding authorization token
  """
  @spec fetch_portal_url(String.t(), map()) :: Tesla.Env.result()
  def fetch_portal_url(url, payload),
    do: post(url, payload)
end
