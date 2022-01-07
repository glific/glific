defmodule Glific.Providers.GupshupEnterpriseContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup Enterprise
  """

  use Publicist

  alias Glific.{
    BSPContacts,
    Contacts.Contact,
    Partners,
    Providers.Gupshup.Enterprise.ApiClient
  }

  @behaviour Glific.Providers.ContactBehaviour

  @doc """
    Update a contact phone as opted in
  """
  @impl Glific.Providers.ContactBehaviour

  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    ApiClient.optin_contact(organization_id, %{"phone_number" => attrs.phone})
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        %{
          name: attrs[:name],
          phone: attrs.phone,
          organization_id: organization_id,
          optin_time: Map.get(attrs, :optin_time, DateTime.utc_now()),
          optin_status: true,
          optin_method: Map.get(attrs, :method, "BSP"),
          language_id:
            Map.get(attrs, :language_id, Partners.organization_language_id(organization_id)),
          bsp_status: :hsm
        }
        |> BSPContacts.Contact.create_or_update_contact()

      _ ->
        {:error, ["gupshup_enterprise", "couldn't connect"]}
    end
  end
end
