defmodule Glific.Providers.GupshupContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup
  """

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Providers.Gupshup.ApiClient
  }

  @behaviour Glific.Providers.ContactBehaviour

  @doc """
    Update a contact phone as opted in
  """
  @impl Glific.Providers.ContactBehaviour
  @spec optin_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    organization = Partners.organization(organization_id)
    bsp_credentials = organization.services["bsp"]

    url =
      bsp_credentials.keys["api_end_point"] <>
        "/app/opt/in/" <> bsp_credentials.secrets["app_name"]

    api_key = bsp_credentials.secrets["api_key"]

    ApiClient.post(url, %{user: attrs.phone}, headers: [{"apikey", api_key}])
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        %{
          name: attrs[:name],
          phone: attrs.phone,
          organization_id: organization_id,
          optin_time: DateTime.utc_now(),
          bsp_status: :hsm
        }
        |> Contacts.create_contact()

      _ ->
        {:error, ["gupshup", "couldn't connect"]}
    end
  end
end
