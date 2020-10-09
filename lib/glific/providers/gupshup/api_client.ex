defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """
  alias Plug.Conn.Query

  use Tesla
  plug Tesla.Middleware.Logger, log_level: :debug

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

  @doc """
  Returning mock Tesla value when message is send from simulator
  """
  @spec simulator_post :: {:ok, map()}
  def simulator_post do
    message_id = Faker.String.base64(36)
    {:ok,
    %Tesla.Env{
      body: "{\"status\":\"submitted\",\"messageId\":\"simu-#{message_id}\"}",
      method: :post,
      status: 200,
    }}
  end

end
