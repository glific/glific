defmodule GlificWeb.Providers.Maytapi.Router do
  @moduledoc """
  A maytapi router
  """

  use GlificWeb, :router

  alias GlificWeb.Providers.Maytapi.Controllers

  scope "/maytapi", Controllers do
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

    scope "/message-event" do
      post("/handler", MessageEventController, :handler)
      post("/*unknown", DefaultController, :unknown)
    end

    post("/*unknown", DefaultController, :unknown)
  end
end
