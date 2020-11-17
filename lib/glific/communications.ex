defmodule Glific.Communications do
  @moduledoc """
  Glific interface for all provider communication
  """

  alias Glific.Partners

  @doc """
  Get the current provider handler based on the config
  """
  @spec provider_handler(non_neg_integer) :: atom()
  def provider_handler(organization_id) do
    bsp_credential = Partners.organization(organization_id).services["bsp"]
    ("Elixir." <> bsp_credential.keys["handler"]) |> String.to_existing_atom()
  end

  @doc """
  Get the current provider worker based on the organization | Config | Defaultconfig
  """
  @spec provider_worker(non_neg_integer) :: atom()
  def provider_worker(organization_id) do
    bsp_credential = Partners.organization(organization_id).services["bsp"]
    ("Elixir." <> bsp_credential.keys["worker"]) |> String.to_existing_atom()
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
    # we will delete the default value setting, the minute we know what to do with tags
    # and how to get the organization id
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      data,
      [{topic, organization_id}]
    )

    data
  end
end
