defmodule Glific.Flows.Webhooks.ResultTranslator do
  @moduledoc """
  Temporary adapter: converts sync webhook `call/2` results into the legacy shape
  consumed by the flow engine's success/failure routing.

  The flow engine routes on `is_map/1` (map → Success branch, string → Failure branch), so:

  * `{:ok, value}` → a result map → Success branch (a `map` value passes through unchanged;
    a struct/scalar is encoded into a map).
  * `{:error, error_type, message}` → the bare `message` string → Failure branch (the type atom
    was already consumed for reporting by `Instrumentation`, so it's stripped here).
  * anything else passes through unchanged (defensive).

  Migrated webhooks return `{:ok, _}` / `{:error, _, _}` from `call/2`; the dispatcher applies
  `to_legacy_structure/2` after the call. Webhook modules must not call this module directly.

  Remove once the flow engine routes on an application-level `success` field instead of `is_map/1`.
  """

  alias Glific.Flows.Webhooks.Geolocation.Address

  @type encoder :: (term() -> map())

  @doc """
  Translates a `call/2` return value into the legacy format for the flow engine.

  `{:ok, value}` is encoded via `encoder_for/1`; a typed error becomes its message string;
  anything else passes through unchanged.
  """
  @spec to_legacy_structure(term(), module()) :: map() | String.t() | term()
  def to_legacy_structure({:ok, value}, module) do
    encoder_for(module).(value)
  end

  def to_legacy_structure({:error, _error_type, message}, _module) when is_binary(message) do
    message
  end

  def to_legacy_structure(other, _module), do: other

  @doc "Encoder for `{:ok, value}` when no module-specific encoder is registered."
  @spec encoder_for(module()) :: encoder()
  def encoder_for(Glific.Flows.Webhooks.Geolocation), do: &Address.to_flow_map/1
  def encoder_for(_module), do: &default_encoder/1

  # A result map is already the flow payload — pass it through. A struct/scalar is wrapped into
  # a map (`success: true`) so the flow engine still sees a map on the Success branch.
  @spec default_encoder(term()) :: map()
  defp default_encoder(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.put(:success, true)
  end

  defp default_encoder(map) when is_map(map), do: map

  defp default_encoder(value), do: %{success: true, value: value}
end
