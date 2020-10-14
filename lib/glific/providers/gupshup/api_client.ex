defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """
  alias Plug.Conn.Query

  use Tesla
  plug Tesla.Middleware.Logger, log_level: :debug

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

end
