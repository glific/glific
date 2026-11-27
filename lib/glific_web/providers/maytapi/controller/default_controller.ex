defmodule GlificWeb.Providers.Maytapi.Controllers.DefaultController do
  @moduledoc false

  use GlificWeb, :controller

  require Logger

  alias Glific.Providers.Maytapi.Instrumentation

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc false
  @spec unknown(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unknown(conn, params) do
    organization_id = conn.assigns[:organization_id]
    # the path comes from the webhook body, so it goes to the log and not into a metric tag
    Instrumentation.track_receive("unhandled_event", organization_id)

    Logger.info(
      "Unhandled Maytapi event #{Enum.join(List.wrap(params["unknown"]), "/")} for org #{organization_id}"
    )

    handler(conn, params, "unknown handler")
  end
end
