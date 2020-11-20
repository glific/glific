defmodule GlificWeb.Providers.Gupshup.Router do
  @moduledoc """
  A Gupshup router which will redirect all the gupsup incoming request to there controller actions.
  """

  use GlificWeb, :router

  alias GlificWeb.Providers.Gupshup.Controllers

  @doc """
  Need to match the following type specs from the gupshup documentation
  # type
  user-event
    # payload.type
    sandbox-start
    opted-in      # payload.type == opted-in
    opted-out     # payload.type == opted-out
  message-event   $ type == message-event
    # payload.type
    enqueued
    failed
    sent
    delivered
    read
  message
    # payload.type
    text
    image
    file
    audio
    video
    contact
    location
  """
  scope "/gupshup", Controllers do
    scope "/user-event" do
      post("/opted-in", UserEventController, :opted_in)
      post("/opted-out", UserEventController, :opted_out)
      post("/*unknown", DefaultController, :unknown)
    end

    scope "/message-event" do
      post("/enqueued", MessageEventController, :enqueued)
      post("/failed", MessageEventController, :failed)
      post("/sent", MessageEventController, :sent)
      post("/delivered", MessageEventController, :delivered)
      post("/read", MessageEventController, :read)
      post("/*unknown", DefaultController, :unknown)
    end

    scope "/message" do
      post("/text", MessageController, :text)
      post("/quick_reply", MessageController, :text)
      post("/image", MessageController, :image)
      post("/file", MessageController, :file)
      post("/audio", MessageController, :audio)
      post("/video", MessageController, :video)
      post("/location", MessageController, :location)
      post("/*unknown", DefaultController, :unknown)
    end

    post("/*unknown", DefaultController, :unknown)
  end
end
