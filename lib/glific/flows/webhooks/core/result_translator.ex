defmodule Glific.Flows.Webhooks.ResultTranslator do
  @moduledoc """
  Temporary adapter: converts sync webhook `call/2` results into the legacy shape
  consumed by the flow engine's success/failure routing.

  Until the flow engine routes on an application-level `success` field (rather than
  checking `is_map/1`):

  * `{:ok, value}` → results map (`success: true` + payload) → Success branch
  * `{:error, message}` → bare string → Failure branch
  * other return values pass through unchanged (legacy map responses)

  Migrated webhooks return `{:ok, _}` / `{:error, _}` from `call/2`; the
  dispatcher applies `to_legacy_structure/2` after the call. Webhook modules must
  not call this module directly.

  Remove once all webhooks are migrated and the flow engine is updated.
  """

  alias Glific.Flows.Webhooks.Geolocation.Address

  @type encoder :: (term() -> map())

  @doc """
  Translates a `call/2` return value into the legacy format for the flow engine.

  Tuple results are encoded via `encoder_for/1`; legacy maps and other values
  are returned unchanged.
  """
  @spec to_legacy_structure(term(), module()) :: map() | String.t() | term()
  def to_legacy_structure({:ok, value}, module) do
    encode_tuple({:ok, value}, encoder_for(module))
  end

  def to_legacy_structure({:error, message}, module) when is_binary(message) do
    encode_tuple({:error, message}, encoder_for(module))
  end

  def to_legacy_structure(other, _module), do: other

  @doc "Encoder for `{:ok, value}` when no module-specific encoder is registered."
  @spec encoder_for(module()) :: encoder()
  def encoder_for(Glific.Flows.Webhooks.Geolocation), do: &Address.to_flow_map/1
  def encoder_for(_module), do: &default_encoder/1

  @spec encode_tuple({:ok, term()} | {:error, String.t()}, encoder()) :: map() | String.t()
  defp encode_tuple({:ok, value}, encoder) when is_function(encoder, 1) do
    encoder.(value)
  end

  defp encode_tuple({:error, message}, _encoder) when is_binary(message), do: message

  @spec default_encoder(term()) :: map()
  defp default_encoder(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.put(:success, true)
  end

  defp default_encoder(map) when is_map(map), do: Map.put(map, :success, true)

  defp default_encoder(value), do: %{success: true, value: value}
end
