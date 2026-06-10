defmodule Glific.Flows.Webhooks.Geolocation.Address do
  @moduledoc """
  Parsed geocoding result from Google Maps.

  Internal to the geolocation webhook; encoded for flow results via `to_flow_map/1`
  at the `Glific.Flows.Webhooks.ResultTranslator` boundary.
  """

  @enforce_keys [:city, :state, :country, :postal_code, :district, :address]
  defstruct [:city, :state, :country, :postal_code, :district, :address]

  @type t :: %__MODULE__{
          city: String.t(),
          state: String.t(),
          country: String.t(),
          postal_code: String.t(),
          district: String.t(),
          address: String.t()
        }

  @doc """
  Flow-results map shape (atom keys) stored on the flow context.
  """
  @spec to_flow_map(t()) :: map()
  def to_flow_map(%__MODULE__{} = address) do
    address
    |> Map.from_struct()
    |> Map.put(:success, true)
  end
end
