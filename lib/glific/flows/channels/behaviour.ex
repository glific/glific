defmodule Glific.Flows.Channels.Behaviour do
  @moduledoc """
  Contract for the work a single channel refuses to run.

  One implementation per channel, looked up by `Glific.Flows.Channels`. A refusal is returned as
  a `{:channel, Flow, message, node_uuid}` tuple; the publish policy that tuple triggers belongs
  to `Glific.Flows`, not to the implementations.
  """

  @type error :: {module(), String.t(), Ecto.UUID.t() | nil}
  @type errors :: list()

  @callback validate_node(node :: map(), errors :: errors()) :: errors()
  @callback validate_sub_flow(
              sub_flow :: map(),
              errors :: errors(),
              node_uuid :: Ecto.UUID.t() | nil
            ) :: errors()
end
