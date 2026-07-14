defmodule Glific.Flows.Webhooks.ResultTranslator do
  @moduledoc """
  Temporary adapter converting sync `call/2` results into the legacy shape the flow engine routes
  on via `is_map/1` (map → Success, string → Failure): `{:ok, value}` → encoded map,
  `{:error, _type, message}` → the bare message (the type atom was already reported), anything
  else passes through. Remove once the flow engine routes on an explicit `success` field.
  """

  alias Glific.Flows.Webhooks.Geolocation.Address

  @type encoder :: (term() -> map())

  @doc "Translate a `call/2` return into the legacy map/string the flow engine routes on."
  @spec to_legacy_structure(term(), module()) :: map() | String.t() | term()
  def to_legacy_structure({:ok, value}, module) do
    encoder_for(module).(value)
  end

  def to_legacy_structure({:error, _error_type, message}, _module) when is_binary(message) do
    message
  end

  def to_legacy_structure(other, _module), do: other

  @doc "Return the `{:ok, value}` encoder for a module (module-specific or the default)."
  @spec encoder_for(module()) :: encoder()
  def encoder_for(Glific.Flows.Webhooks.Geolocation), do: &Address.to_flow_map/1
  def encoder_for(_module), do: &default_encoder/1

  # A map is already the flow payload; a struct/scalar is wrapped (`success: true`) so the engine
  # still sees a map on the Success branch.
  @spec default_encoder(term()) :: map()
  defp default_encoder(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.put(:success, true)
  end

  defp default_encoder(map) when is_map(map), do: map

  defp default_encoder(value), do: %{success: true, value: value}
end
