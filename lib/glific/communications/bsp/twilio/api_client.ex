defmodule Glific.Communications.BSP.Twilio.ApiClient do
  use Tesla
  plug Tesla.Middleware.BaseUrl, "https://api.twilio.io/sm/api/v1"

  plug Tesla.Middleware.Headers, [
    {"apikey", "380a3225dc604909c9cb840"}
  ]

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Plug.Conn.Query.encode/1
end
