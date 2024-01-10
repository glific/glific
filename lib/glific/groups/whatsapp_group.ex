defmodule Glific.Groups.WhatsappGroup do
  @moduledoc """
  Whatsapp groups context.
  """

  alias Glific.{
    Groups,
    Providers.Maytapi.ApiClient
  }

  @doc """
  Fetches group using maytapi API and sync it in Glific

  ## Examples

      iex> list_wa_groups()
      [%Group{}, ...]

  """
  @spec list_wa_groups(non_neg_integer()) :: list() | {:error, any()}
  def list_wa_groups(org_id) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_groups(org_id),
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
