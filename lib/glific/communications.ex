defmodule Glific.Communications do
  @moduledoc """
  Glific interface for all provider communication
  """

  alias Glific.{Contacts, Messages.Message, Partners}
  require Logger

  @doc """
  Get the current provider handler based on the config
  """
  @spec provider_handler(non_neg_integer) :: atom()
  def provider_handler(organization_id) do
    bsp_credential = Partners.organization(organization_id).services["bsp"]
    ("Elixir." <> bsp_credential.keys["handler"]) |> Glific.safe_string_to_atom()
  end

  @doc """
  Get the current provider worker based on the organization | Config | Default config
  """
  @spec provider_worker(non_neg_integer) :: atom()
  def provider_worker(organization_id) do
    bsp_credential = Partners.organization(organization_id).services["bsp"]
    ("Elixir." <> bsp_credential.keys["worker"]) |> Glific.safe_string_to_atom()
  end

  @doc """
  Unified function to publish data on the graphql subscription endpoint. This  is still looking for a
  place to actually reside. This is a good next stop for now

  For now the data types are Message and all join Tag tables
  """
  @spec publish_data({:ok, any()} | any(), atom(), non_neg_integer) :: any()
  def publish_data({:ok, data}, topic, organization_id) do
    publish_data(data, topic, organization_id)
  end

  def publish_data(data, topic, organization_id) do
    if is_struct(data) do
      Logger.info("Publishing: #{Ecto.get_meta(data, :source)}, #{topic}:#{organization_id}")
    else
      Logger.info("Publishing: #{Glific.SafeLog.safe_inspect(data)}, #{topic}:#{organization_id}")
    end

    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      data,
      [{topic, organization_id}]
    )

    data
  end

  @doc """
  Publish an extra `sent_simulator_message` / `received_simulator_message` subscription event
  when `message.contact` (must be preloaded) is a simulator contact, so the console's simulator
  view gets a live feed regardless of which channel (WhatsApp or web) the message travels on.
  """
  @spec publish_simulator(Message.t() | nil, atom()) :: Message.t() | nil
  def publish_simulator(message, type) when type in [:sent_message, :received_message] do
    if Contacts.simulator_contact?(message.contact.phone) do
      message_type =
        if type == :sent_message,
          do: :sent_simulator_message,
          else: :received_simulator_message

      publish_data(message, message_type, message.organization_id)
    end

    message
  end

  def publish_simulator(message, _type), do: message
end
