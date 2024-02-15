defmodule Glific.Groups.WhatsappGroup do
  @moduledoc """
  Whatsapp groups context.
  """

  alias Glific.{
    Groups,
    Providers.Maytapi.ApiClient,
    WAManagedPhones
  }

  @doc """
  Fetches group using maytapi API and sync it in Glific
  """
  @spec list_wa_groups(non_neg_integer()) :: :ok
  def list_wa_groups(org_id) do
    wa_managed_phones = WAManagedPhones.list_wa_managed_phones(%{organization_id: org_id})

    Enum.each(wa_managed_phones, fn wa_managed_phone ->
      do_list_wa_groups(org_id, wa_managed_phone.phone_id)
    end)
  end


  @spec do_list_wa_groups(non_neg_integer(), non_neg_integer()) :: list() | {:error, any()}
  defp do_list_wa_groups(org_id, phone_id) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_groups(org_id, phone_id),
         {:ok, decoded} <- Jason.decode(body) do
      decoded
      |> get_group_names()
      |> create_whatsapp_groups(org_id)
    else
      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, body}

      {:error, message} ->
        {:error, inspect(message)}
    end
  end

  defp get_group_names(%{"data" => groups}) when is_list(groups) do
    Enum.map(groups, fn group -> %{name: group["name"], bsp_id: group["id"]} end)
  end

  @spec create_whatsapp_groups(list(), non_neg_integer) :: list()
  defp create_whatsapp_groups(group_names, org_id) do
    Enum.map(
      group_names,
      fn group ->
        Groups.create_group(%{
          label: group.name,
          group_type: "WA",
          organization_id: org_id,
          bsp_id: group.bsp_id
        })
      end
    )
  end
end
