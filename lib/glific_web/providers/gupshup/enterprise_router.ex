defmodule GlificWeb.Providers.Gupshup.Enterprise.Router do
  @moduledoc """
  A Gupshup router which will redirect all the gupsup incoming request to there controller actions.
  """

  use GlificWeb, :router

  alias GlificWeb.Providers.Gupshup.Enterprise.Controllers

  scope "/gupshup", Controllers do
    scope "/message" do
      post("/text", MessageController, :text)
    end
  end
end
