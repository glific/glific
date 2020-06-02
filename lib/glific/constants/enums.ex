defmodule Glific.Constants.Enums do
  @moduledoc """
  The Enums constant are where all enum values across our entire
  application should be defined. This is the source of truth for
  all enums
  """

  defmacro __using__(_opts) do
    quote do
      # standard first part of a tuple for many api calls
      @api_status_const [:ok, :error]

      # the status determines if we can send a message to the contact
      @contact_status_const [:failed, :invalid, :processing, :valid]

      # the direction of the messages: inbound: bsp to glific, outbound: glific to bsp
      @message_flow_const [:inbound, :outbound]

      # the status of the message as indicated by the bsp
      @message_status_const [:sent, :delivered, :enqueued, :error, :read, :received]

      # the different possible types of message
      @message_types_const [:audio, :contact, :document, :hsm, :image, :location, :text, :video]

      # the possible sort direction for lists/rows, typically used in DB operations
      @sort_order_const [:asc, :desc]

    end
  end
end
