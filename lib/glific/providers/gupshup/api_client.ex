defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """
  alias Plug.Conn.Query

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug Tesla.Middleware.Logger

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
end
