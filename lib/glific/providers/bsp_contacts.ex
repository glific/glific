defmodule Glific.Providers.Contacts do
  @moduledoc """
  A common provider contacts module to handle opted in contacts irrespective of BSP
  """
  alias Glific.{
    BSPContacts,
    Partners
  }

  @doc """
  Create or update contact as opted in when successfully marked as opted in user
  """
  @spec create_or_update_contact(map(), pos_integer()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_contact(attrs, organization_id) do
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
  end
end
