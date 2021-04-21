defmodule GlificWeb.API.V1.OnboardController do
  @moduledoc """
  The Glific Onboarding Controller
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.Saas.Onboard
  alias Plug.Conn

  @doc false
  @spec setup(Conn.t(), map()) :: Conn.t()
  def setup(conn, params),
    do: json(conn, Onboard.setup(params))
end
