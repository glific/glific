defmodule Glific.Communications do
  @moduledoc """
  Glific interface for all provider communication
  """

  alias Glific.{
    Messages.Message,
    Partners,
    Tags.ContactTag,
    Tags.MessageTag,
    Tags.TemplateTag
  }

  @doc """
  Get the current provider handler based on the config
  """
  @spec provider_handler(non_neg_integer) :: atom()
  def provider_handler(organization_id),
    do: Partners.organization(organization_id).provider_handler

  @doc """
  Get the current provider worker based on the organization | Config | Defaultconfig
  """
  @spec provider_worker(non_neg_integer) :: atom()
  def provider_worker(organization_id),
    do: Partners.organization(organization_id).provider_worker

  @doc """
  Unified function to publish data on the graphql subscription endpoint. This  is still looking for a
  place to actually reside. This is a good next stop for now

  For now the data types are Message and MessageTag
  """

  @spec publish_data(
          {:ok, Message.t() | MessageTag.t() | TemplateTag.t() | ContactTag.t()},
          atom()
        ) ::
          Message.t() | MessageTag.t() | TemplateTag.t() | ContactTag.t()
  def publish_data({:ok, data}, topic) do
    publish_data(data, topic)
  end

  @spec publish_data(Message.t() | MessageTag.t() | TemplateTag.t() | ContactTag.t(), atom()) ::
          Message.t() | MessageTag.t() | TemplateTag.t() | ContactTag.t()
  def publish_data(data, topic) do
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      data,
      [{topic, :glific}]
    )

    data
  end
end
