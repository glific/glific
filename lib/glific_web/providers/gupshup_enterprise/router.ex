defmodule GlificWeb.Providers.Gupshup.Enterprise.Router do
  @moduledoc """
  A Gupshup router which will redirect all the gupsup incoming request to there controller actions.
  """

  use GlificWeb, :router

  alias GlificWeb.Providers.Gupshup.Enterprise.Controllers

  scope "/gupshup", Controllers do
    scope "/message" do
      post("/text", MessageController, :text)
      post("/image", MessageController, :image)
      post("/video", MessageController, :video)
      post("/audio", MessageController, :audio)
      post("/voice", MessageController, :audio)
      post("/document", MessageController, :document)
      post("/location", MessageController, :location)
      post("/button", MessageController, :button)
      post("/interactive", MessageController, :interactive)
    end
  end
end
