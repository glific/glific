defmodule Glific.Clients.BharatRohan do
  @moduledoc """
  Custom webhook implementation specific to BharatRohan use case
  """

  alias Glific.Messages

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("previous_advisories", fields) do
    Messages.list_messages(%{
      filter: %{flow_label: fields["flow_label"], contact_id: fields["contact_id"]},
      opts: %{limit: 3}
    })
    |> Enum.each(fn message ->
      Messages.create_and_send_message(%{
        body: message.body,
        flow: message.flow,
        media_id: message.media_id,
        organization_id: message.organization_id,
        receiver_id: message.receiver_id,
        sender_id: message.sender_id,
        type: message.type,
        user_id: message.user_id
      })
    end)

    %{success: true}
  end

  def webhook("parse_weather_report", fields) do
    weather_report = fields["results"]["weather_report"]
    %{report_msg: get_report_msg(weather_report)}
  end

  def webhook(_, _fields),
    do: %{}

  @doc """
    Get weather report message
  """
  @spec get_report_msg(map()) :: String.t()
  def get_report_msg(weather_report) do
    days_map = Map.get(weather_report, "days", %{})
    days = Map.values(days_map)

    _formatted_output =
      Enum.reduce(days, "", fn day, acc ->
        windspeed = Map.get(day, "windspeed", "")
        winddir = Map.get(day, "winddir", "")
        tempmin = Map.get(day, "tempmin", "")
        tempmax = Map.get(day, "tempmax", "")
        datetime = Map.get(day, "datetime", "")
        precipitation = Map.get(day, "precip", "")
        humidity = Map.get(day, "humidity", "")

        line = """
        *Date:* #{datetime}
        *Min Temperature:* #{tempmin} °C
        *Max Temperature:* #{tempmax} °C
        *Precipitation:* #{precipitation} mm
        *Humidity:* #{humidity} %
        *Wind speed:* #{windspeed} km/h
        *Wind Direction:* #{winddir} °
        """

        acc <> line <> "\n\n"
      end)
  end
end
