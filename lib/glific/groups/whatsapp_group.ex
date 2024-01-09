defmodule Glific.Groups.WhatsappGroup do

  alias Glific.{
    Groups
  }

  @spec get_whatsapp_group_details() :: list() | {:error, any()}
  def get_whatsapp_group_details do
    #the id and token will come from the maytapi account
    phone_id = 40478
    product_id = "0cc85749-9c6f-4671-997d-a3bb95933058"
    token = "001ed56d-59e6-4aee-8a50-2a833635fcfe"

    # cURL to get groups
    url = "https://api.maytapi.com/api/#{product_id}/#{phone_id}/getGroups"

    headers = [
      {"accept", "application/json"},
      {"x-maytapi-key", token}
    ]


    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <- Tesla.get(url, headers: headers),
         {:ok, decoded} <- Jason.decode(body) do
      get_group_names(decoded)
      |> insert_whatsapp_groups()
    else
      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, body}
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
