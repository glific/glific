defmodule GlificWeb.Providers.Gupshup.Router do
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
  scope "/gupshup" do
    scope "/user-event" do
      post("/", Controllers.UserEventController, :user_event)
      post("/sandbox-start",Controllers.UserEventController, :sandbox_start)
      post("/opted-in", Controllers.UserEventController, :opted_in)
      post("/opted-out", Controllers.UserEventController, :opted_out)
      post("/unknown", Controllers.DefaultController, :unknown)
    end

    scope "/message-event" do
      post("/", Controllers.MessageEventController, :message_event)
      post("/enqueued", Controllers.MessageEventController, :enqueued)
      post("/failed", Controllers.MessageEventController, :failed)
      post("/sent", Controllers.MessageEventController, :sent)
      post("/delivered", Controllers.MessageEventController, :delivered)
      post("/unknown", Controllers.DefaultController, :unknown)
    end

    scope "/message" do
      post("/", Controllers.MessageController, :message)
      post("/text", Controllers.MessageController, :text)
      post("/image", Controllers.MessageController, :image)
      post("/file", Controllers.MessageController, :file)
      post("/audio", Controllers.MessageController, :audio)
      post("/video", Controllers.MessageController, :video)
      post("/contact", Controllers.MessageController, :contact)
      post("/location", Controllers.MessageController, :location)
      post("/unknown", Controllers.DefaultController, :unknown)
    end

    post("/unknown/unknown", Controllers.DefaultController, :unknown)
  end
end
