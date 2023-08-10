defmodule Glific.Clients.Bandhu do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.Clients.CommonWebhook

  @housing_url "https://housing.bandhumember.work/api/housing/create_sql_query_from_json"

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("mock_bandhu_for_profile_check", _fields) do
    %{
      profile_count: 0,
      profiles: []
    }
  end

  def webhook("fetch_user_profiles", fields) do
    profile_count =
      get_in(fields, ["results", "parent", "bandhu_profile_check_mock", "data", "profile_count"]) ||
        0

    profiles =
      get_in(fields, ["results", "parent", "bandhu_profile_check_mock", "data", "profiles"]) ||
        nil

    {index_map, message_list} =
      if is_nil(profiles),
        do: {%{}, ["No profiles found"]},
        else: format_profile_message(profiles)

    %{
      profile_selection_message: Enum.join(message_list, "\n"),
      index_map: Jason.encode!(index_map),
      profile_count: profile_count,
      x_api_key: "nothing"
    }
  end

  def webhook("set_contact_profile", fields) do
    index_map = Jason.decode!(fields["index_map"])
    profile_number = fields["profile_number"]

    if Map.has_key?(index_map, profile_number) do
      profile = index_map[profile_number]
      %{profile: profile, is_valid: true}
    else
      %{profile: %{}, is_valid: false}
    end
  end

  def webhook("test", _fields),
    do: %{
      "media_url" =>
        "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png"
    }

  def webhook("jugalbandi", fields), do: CommonWebhook.webhook("jugalbandi", fields)
  def webhook("jugalbandi-voice", fields), do: CommonWebhook.webhook("jugalbandi-voice", fields)

  def webhook("jugalbandi-json", fields) do
    CommonWebhook.webhook("jugalbandi", fields)
    |> parse_bandhu_json()
  end

  def webhook("housing_sql", fields) do
    header = [{"Content-Type", "application/json"}]

    Tesla.post(@housing_url, Jason.encode!(fields), headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> get_in(["data"])
        |> hd

      {_status, _response} ->
        %{success: false, response: "Error response received"}
    end
  end

  def webhook(_, _fields), do: %{}

  @spec parse_bandhu_json(map()) :: map()
  defp parse_bandhu_json(%{success: true} = json) do
    case Jason.decode(json["answer"]) do
      {:ok, decoded_response} ->
        Map.put(decoded_response, :success, true)

      {:error, _} ->
        Map.put(%{response: json["answer"]}, :success, false)
    end
  end

  defp parse_bandhu_json(%{success: false} = _json),
    do: %{success: false, response: "Error Json received"}

  defp format_profile_message(profiles) do
    profiles
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, []}, fn {profile, index}, {index_map, message_list} ->
      profile_name = profile["name"]
      user_roles = profile["user_roles"]["role_type"]

      {
        Map.put(index_map, index, profile),
        message_list ++ ["Type *#{index}* for #{profile_name} (#{user_roles})"]
      }
    end)
  end
end
