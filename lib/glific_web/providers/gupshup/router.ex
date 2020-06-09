defmodule GlificWeb.Provider.Gupshup.Router do
  use GlificWeb, :router

  alias GlificWeb.Provider.Gupshup.Controllers

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
  scope "/gupshup", TwoWayWeb do
    scope "/user-event" do
      post("/", Controllers.GupshupUserEventController, :user_event)
      post("/sandbox-start",Controllers.GupshupUserEventController, :sandbox_start)
      post("/opted-in", Controllers.GupshupUserEventController, :opted_in)
      post("/opted-out", Controllers.GupshupUserEventController, :opted_out)
      post("/unknown", Controllers.GupshupController, :unknown)
    end

    scope "/message-event" do
      post("/", Controllers.GupshupMessageEventController, :message_event)
      post("/enqueued", Controllers.GupshupMessageEventController, :enqueued)
      post("/failed", Controllers.GupshupMessageEventController, :failed)
      post("/sent", Controllers.GupshupMessageEventController, :sent)
      post("/delivered", Controllers.GupshupMessageEventController, :delivered)
      post("/unknown", Controllers.GupshupController, :unknown)
    end

    scope "/message" do
      post("/", Controllers.GupshupMessageController, :message)
      post("/text", Controllers.GupshupMessageController, :text)
      post("/image", Controllers.GupshupMessageController, :image)
      post("/file", Controllers.GupshupMessageController, :file)
      post("/audio", Controllers.GupshupMessageController, :audio)
      post("/video", Controllers.GupshupMessageController, :video)
      post("/contact", Controllers.GupshupMessageController, :contact)
      post("/location", Controllers.GupshupMessageController, :location)
      post("/unknown", Controllers.GupshupController, :unknown)
    end

    post("/unknown/unknown", Controllers.GupshupController, :unknown)
  end
end
