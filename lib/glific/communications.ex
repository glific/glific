defmodule Glific.Communications do
  @moduledoc """
  Glific interface for all provider communication
  """

  alias Glific.{
    Messages.Message,
    Tags.MessageTag
  }

  @doc """
  Get the current provider based on the config
  """
  @spec provider :: atom()
  def provider, do: Application.fetch_env!(:glific, :provider)

  @doc """
  Get the current provider worker based on the organization | Config | Defaultconfig
  """
  @spec provider_worker :: atom()
  def provider_worker, do: Application.fetch_env!(:glific, :provider_worker)

  @doc """
  Unified function to publish data on the graphql subscription endpoint. This  is still looking for a
  place to actually reside. This is a good next stop for now

  For now the data types are Message and MessageTag
  """

  @spec publish_data({:ok, Message.t() | MessageTag.t()}, atom()) :: Message.t() | MessageTag.t()
  def publish_data({:ok, data}, topic) do
    publish_data(data, topic)
  end

  @spec publish_data(Message.t() | MessageTag.t(), atom()) :: Message.t() | MessageTag.t()
  def publish_data(data, topic) do
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      data,
      [{topic, :glific}]
    )

    data
  end
end
