defmodule Glific.Flows.Webhooks.Geolocation do
  @moduledoc """
  Reverse-geocode `lat` / `long` to a structured address via Google Maps.

  First webhook migrated to the `Glific.Flows.Webhooks` architecture — see
  `plans/webhook-refactor.md` for the broader plan. Behaviour is preserved
  one-for-one with the legacy `Glific.Clients.CommonWebhook.webhook("geolocation", ...)`
  clause; the centralised dispatcher adds AppSignal reporting on failure
  paths.

  Returns `{:ok, Address.t()}` or `{:error, String.t()}` from `call/2`. The
  dispatcher encodes those tuples for the flow engine (map on success, string
  on failure) via `Glific.Flows.Webhooks.ResultTranslator`.
  """

  use Glific.Flows.Webhooks.Sync, name: "geolocation"

  alias Glific.Flows.Webhooks.Geolocation.Address

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, Address.t()} | {:error, String.t()}
  def call(fields, _ctx), do: geocode(fields)

  @spec geocode(map()) :: {:ok, Address.t()} | {:error, String.t()}
  defp geocode(fields) do
    lat = (fields["lat"] || "") |> to_string() |> String.trim()
    long = (fields["long"] || "") |> to_string() |> String.trim()

    if lat == "" or long == "" do
      {:error, "Missing lat or long field"}
    else
      api_key = Glific.get_google_maps_api_key()

      url =
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{lat},#{long}&key=#{api_key}"

      do_geocode(url)
    end
  end

  @doc false
  @spec client() :: Tesla.Client.t()
  def client do
    # Logger middleware is intentionally omitted: the geocoding URL contains
    # the Google Maps API key as a query parameter and must not be logged.
    Tesla.client(
      [
        {Tesla.Middleware.Telemetry, metadata: %{provider: "google_maps_geocoding"}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end

  @spec do_geocode(String.t()) :: {:ok, Address.t()} | {:error, String.t()}
  defp do_geocode(url) do
    case Tesla.get(client(), url) do
      {:ok, %Tesla.Env{body: body}} ->
        decode_response(body)

      {:error, reason} ->
        {:error,
         "Could not connect to the geocoding service (#{inspect(reason)}). Check your network connection and try again."}
    end
  end

  @spec decode_response(String.t()) :: {:ok, Address.t()} | {:error, String.t()}
  defp decode_response(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) ->
        decode_geocode_response(decoded)

      {:ok, _unexpected} ->
        {:error,
         "The geocoding service returned an unexpected response format. Please try again later."}

      {:error, _decode_error} ->
        {:error, "The geocoding service returned an unreadable response. Please try again later."}
    end
  end

  # The Geocoding API contract is defined purely by the `status` field in the JSON body —
  # the docs make no guarantees about HTTP status codes.
  # See https://developers.google.com/maps/documentation/geocoding/requests-geocoding#StatusCodes
  @spec decode_geocode_response(map()) :: {:ok, Address.t()} | {:error, String.t()}
  defp decode_geocode_response(%{"status" => "OK", "results" => results}),
    do: parse_results(results)

  defp decode_geocode_response(%{"status" => status} = decoded) do
    {:error, geocode_status_error(status, Map.get(decoded, "error_message"))}
  end

  # Must come after the status-bearing clause above — a response with both "status" and
  # "results" should be routed by status, not treated as a no-status success.
  defp decode_geocode_response(%{"results" => results}), do: parse_results(results)

  defp decode_geocode_response(_unexpected) do
    {:error,
     "The geocoding service returned an unexpected response format. Please try again later."}
  end

  @spec geocode_status_error(String.t(), String.t() | nil) :: String.t()
  defp geocode_status_error("ZERO_RESULTS", _error_message) do
    "No address found for these coordinates. Verify that the latitude and longitude are correct and fall within a supported region."
  end

  defp geocode_status_error("REQUEST_DENIED", error_message) do
    wrap_gmaps_error(
      "Geocoding request was denied.",
      error_message,
      " Check that the Google Maps API key is valid and the Geocoding API is enabled."
    )
  end

  defp geocode_status_error("OVER_QUERY_LIMIT", error_message) do
    wrap_gmaps_error(
      "Geocoding quota exceeded.",
      error_message,
      " Please try again later."
    )
  end

  defp geocode_status_error("INVALID_REQUEST", error_message) do
    wrap_gmaps_error(
      "Invalid geocoding request.",
      error_message,
      " Verify that the latitude and longitude values are valid."
    )
  end

  defp geocode_status_error("UNKNOWN_ERROR", error_message) do
    wrap_gmaps_error(
      "The geocoding service encountered an unexpected error.",
      error_message,
      " Please try again later."
    )
  end

  defp geocode_status_error(status, error_message) do
    wrap_gmaps_error(
      "Geocoding failed (#{status}).",
      error_message,
      " Please try again later."
    )
  end

  @spec wrap_gmaps_error(String.t(), String.t() | nil, String.t()) :: String.t()
  defp wrap_gmaps_error(prefix, error_message, suffix) do
    case blank?(error_message) do
      true -> prefix <> suffix
      false -> prefix <> " " <> String.trim(error_message) <> suffix
    end
  end

  @spec blank?(String.t() | nil) :: boolean()
  defp blank?(value), do: is_nil(value) or value == ""

  @spec parse_results(list()) :: {:ok, Address.t()} | {:error, String.t()}
  defp parse_results([
         %{"address_components" => components, "formatted_address" => formatted_address} | _
       ]) do
    {:ok,
     %Address{
       city: find_component(components, "locality"),
       state: find_component(components, "administrative_area_level_1"),
       country: find_component(components, "country"),
       postal_code: find_component(components, "postal_code"),
       district: find_component(components, "administrative_area_level_3"),
       address: formatted_address
     }}
  end

  defp parse_results(_) do
    {:error,
     "No address found for these coordinates. Verify that the latitude and longitude are correct and fall within a supported region."}
  end

  @spec find_component([map()], String.t()) :: String.t()
  defp find_component(components, type) do
    case Enum.find(components, fn component ->
           types = Map.get(component, "types", [])
           is_list(types) and type in types
         end) do
      nil -> "N/A"
      component -> component["long_name"]
    end
  end
end
