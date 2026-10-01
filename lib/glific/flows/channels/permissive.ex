defmodule Glific.Flows.Channels.Permissive do
  @moduledoc """
  The channel that refuses nothing.

  Used for every channel without its own module, so adding a value to `message_channel_enum`
  cannot crash a publish before its rules are written.
  """

  @behaviour Glific.Flows.Channels.Behaviour

  @doc """
  Accepts every node.
  """
  @impl true
  @spec validate_node(map(), list()) :: list()
  def validate_node(_node, errors), do: errors

  @doc """
  Accepts every sub-flow.
  """
  @impl true
  @spec validate_sub_flow(map(), list(), Ecto.UUID.t() | nil) :: list()
  def validate_sub_flow(_sub_flow, errors, _node_uuid), do: errors
end
