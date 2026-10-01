defmodule Glific.Flows.Channels do
  @moduledoc """
  Dispatches flow validation to the module that owns a channel's refusals.

  `Node` and `Action` call this; they never name a channel implementation. A channel with no
  module registered refuses nothing, so the enum can grow ahead of its rules.
  """

  alias Glific.Flows.Channels.Web

  @channels %{web: Web}

  @doc """
  Refuses the work on this node that the flow's channel cannot run.
  """
  @spec validate(atom(), map(), list()) :: list()
  def validate(channel, node, errors) do
    case Map.get(@channels, channel) do
      nil -> errors
      module -> module.validate_node(node, errors)
    end
  end

  @doc """
  Refuses a sub-flow the entering flow's channel cannot run.
  """
  @spec validate_sub_flow(atom(), map(), list(), Ecto.UUID.t() | nil) :: list()
  def validate_sub_flow(channel, sub_flow, errors, node_uuid) do
    case Map.get(@channels, channel) do
      nil -> errors
      module -> module.validate_sub_flow(sub_flow, errors, node_uuid)
    end
  end
end
