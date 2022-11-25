defmodule GlificWeb.Providers.Airtel.Router do
  @moduledoc """
  A Airtel router which will redirect all the airtel incoming request to there controller actions.
  """

  use GlificWeb, :router

  alias GlificWeb.Providers.Airtel.Controllers

  @doc """
  Need to match the following type specs from the airtel documentation
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
    sticker
    contact
    location
  """
  scope "/airtel", Controllers do
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
      post("/button_reply", MessageController, :quick_reply)
      post("/list_reply", MessageController, :list)
      post("/image", MessageController, :image)
      post("/file", MessageController, :file)
      post("/audio", MessageController, :audio)
      post("/video", MessageController, :video)
      post("/sticker", MessageController, :sticker)
      post("/location", MessageController, :location)
      post("/*unknown", DefaultController, :unknown)
    end

    scope "/billing-event" do
      post("/conversations", BillingEventController, :conversations)
      post("/*unknown", DefaultController, :unknown)
    end

    post("/*unknown", DefaultController, :unknown)
  end
end
