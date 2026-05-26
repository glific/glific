defmodule Glific.Flows.Webhooks.Geolocation do
  @moduledoc """
  Reverse-geocode `lat` / `long` to a structured address via Google Maps.

  First webhook migrated to the `Glific.Flows.Webhooks` architecture — see
  `plans/webhook-refactor.md` for the broader plan. Behaviour is preserved
  one-for-one with the legacy `Glific.Clients.CommonWebhook.webhook("geolocation", ...)`
  clause; the centralised dispatcher adds AppSignal reporting on failure
  paths (matching what the other migrated webhooks like `parse_via_chat_gpt`
  do today).
  """

  use Glific.Flows.Webhooks.Sync, name: "geolocation"

  alias Glific.Metrics

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) :: map()
  def call(fields, _ctx) do
    lat = fields["lat"]
    long = fields["long"]
    api_key = Glific.get_google_maps_api_key()
    url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{lat},#{long}&key=#{api_key}"

    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        decode_success(body)

      {:ok, %Tesla.Env{status: status_code}} ->
        Metrics.increment("Geolocation API Failure")
        %{success: false, error: "Received status code #{status_code}"}

      {:error, reason} ->
        Metrics.increment("Geolocation API Failure")
        %{success: false, error: "HTTP request failed: #{reason}"}
    end
  end

  @spec decode_success(String.t()) :: map()
  defp decode_success(body) do
    %{"results" => results} = Jason.decode!(body)
    Metrics.increment("Geolocation API Success")

    case results do
      [%{"address_components" => components, "formatted_address" => formatted_address} | _] ->
        %{
          success: true,
          city: find_component(components, "locality"),
          state: find_component(components, "administrative_area_level_1"),
          country: find_component(components, "country"),
          postal_code: find_component(components, "postal_code"),
          district: find_component(components, "administrative_area_level_3"),
          address: formatted_address
        }

      _ ->
        %{success: false, error: "No results found"}
    end
  end

  @spec find_component([map()], String.t()) :: String.t()
  defp find_component(components, type) do
    case Enum.find(components, fn component -> type in component["types"] end) do
      nil -> "N/A"
      component -> component["long_name"]
    end
  end
end
