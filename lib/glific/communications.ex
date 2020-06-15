defmodule Glific.Communications do
  @moduledoc """
  Glific interface for all provider communication
  """

  alias Glific.{
    Messages.Message,
    Tags.MessageTag
  }

  @doc """
    Get the current provider based on the organization | Config | Default
  """
  @spec effective_provider :: atom()
  def effective_provider do
    with nil <- provider_per_organisation(),
         nil <- provider_from_config(),
         do: provider_default()
  end

  defp provider_per_organisation do
    nil
  end

  defp provider_from_config do
    case Application.fetch_env!(:glific, :provider) do
      nil -> nil
      provider -> provider
    end
  end

  defp provider_default do
    Glific.Providers.Gupshup
  end

  @doc """
  Unified function to publish data on the graphql subscription endpoint. This  is still looking for a
  place to actually reside. This is a good next stop for now

  For now the data types are Message and MessageTag
  """
  @spec publish_data({:ok, Message.t() | MessageTag.t()}, atom()) :: {:ok, map()}
  def publish_data({:ok, data}, topic) do
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      data,
      [{topic, :glific}]
    )

    {:ok, data}
  end
end
