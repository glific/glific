defmodule Glific.Contacts.Import do
  @moduledoc """
  The Contact Importer Module
  """

  alias Glific.{Contacts, Contacts.Contact, Groups, Partners, Settings}

  @spec cleanup_contact_data(map(), non_neg_integer) :: map()
  defp cleanup_contact_data(data, organization_id) do
    %{
      name: data["name"],
      phone: data["phone"],
      organization_id: organization_id,
      language_id: Enum.at(Settings.get_language_by_label_or_locale(data["language"]), 0).id,
      optin_time: elem(Timex.parse(data["opt_in"], "{YYYY}-{0M}-{0D}"), 1)
    }
  end

  @spec insert_or_update_contact_data(map(), non_neg_integer) :: Contact.t() | map()
  defp insert_or_update_contact_data(contact, group_id) do
    with {:ok, contact} <- Contacts.optin_contact(Map.put(contact, :method, "Import")),
         {:ok, _} <-
           Groups.create_contact_group(%{
             contact_id: contact.id,
             group_id: group_id,
             organization_id: contact.organization_id
           }) do
      contact
    else
      {:error, error} -> %{phone: contact.phone, error: error}
    end
  end

  @doc """
  This method allows importing of contacts to a particular organization and group

  The method takes in a csv file path and adds the contacts to the particular organization
  and group.
  """
  @spec import_contacts(String.t(), integer, integer) :: tuple()
  def import_contacts(file_path, organization_id, group_id) do
    with %{id: organization_id} <- Partners.organization(organization_id),
         # this will raise an exception if group_id is not present
         _group <- Groups.get_group!(group_id) do
      result =
        file_path
        |> Path.expand()
        |> File.stream!()
        |> CSV.decode(headers: true, strip_fields: true)
        |> Enum.map(fn {_, data} -> cleanup_contact_data(data, organization_id) end)
        |> Enum.map(fn contact -> insert_or_update_contact_data(contact, group_id) end)

      errors = result |> Enum.filter(fn contact -> Map.has_key?(contact, :error) end)

      case errors do
        [] -> {:ok, "All contacts added"}
        _ -> {:error, "All contacts could not be added", errors}
      end
    else
      {:error, error} ->
        {:error, "Could not fetch the organization with id #{organization_id}. Error -> #{error}"}
    end
  end
end
