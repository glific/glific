defmodule Glific.Groups.WhatsappGroup do
  require HTTPoison

  alias Glific.{
    Groups
  }

  def get_whatsapp_group_details do
    # Define the cURL
    url = "https://api.maytapi.com/api/0cc85749-9c6f-4671-997d-a3bb95933058/40478/getGroups"

    headers = [
      {"accept", "application/json"},
      {"x-maytapi-key", "001ed56d-59e6-4aee-8a50-2a833635fcfe"}
    ]

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(url, headers),
         {:ok, decoded} <- Jason.decode(body) do
      get_group_names(decoded)
      |> insert_whatsapp_groups()
    else
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "failed: #{reason}"}
    end
  end

  defp get_group_names(%{"data" => groups}) when is_list(groups) do
    Enum.map(groups, fn group -> group["name"] end)
  end

  def insert_whatsapp_groups(group_names) when is_list(group_names) do
    Enum.map(group_names, fn group_name ->
      Groups.create_group(%{label: group_name, group_type: "WA_group", organization_id: 1})
    end)
  end
end
