defmodule Glific.Clients.Bandhu do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("mock_bandhu_for_profile_check", _fields) do
    profile_count = Enum.random(0..5)
    profiles = random_profiles(profile_count)

    %{
      profile_count: profile_count,
      profiles: profiles
    }
  end

  def webhook("fetch_user_profiles", fields) do
    profile_count = get_in(fields, ["data", "profile_count"]) || 3

    profiles = get_in(fields, ["data", "profiles"]) || random_profiles(profile_count)

    {index_map, message_list} = format_profile_message(profiles)

    %{
      profile_selection_message: Enum.join(message_list, "\n"),
      index_map: Jason.encode!(index_map),
      profile_count: profile_count
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

  def webhook(_, _fields), do: %{}

  defp format_profile_message(profiles) do
    profiles
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, []}, fn {profile, index}, {index_map, message_list} ->
      profile_name = profile["name"]

      {
        Map.put(index_map, index, profile),
        message_list ++ ["Type *#{index}* for #{profile_name}"]
      }
    end)
  end

  defp random_profiles(profile_count) do
    1..profile_count
    |> Enum.into([])
    |> Enum.reduce([], fn number, acc ->
      acc ++
        [
          %{
            "name" => "Profile #{number}",
            "profile_id" => "profile_#{number}"
          }
        ]
    end)
  end
end
