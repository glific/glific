defmodule Glific.Contacts.Import do
  @moduledoc """
  The Contact Importer Module
  """

  alias Glific.{Contacts, Contacts.Contact, Groups, Partners, Providers.GupshupContacts, Settings}

  @spec cleanup_contact_data(map(), non_neg_integer) :: map()
  defp cleanup_contact_data(data, organization_id) do
    %{
      name: data["name"],
      phone: data["phone"],
      organization_id: organization_id,
      language_id: Enum.at(Settings.get_language_by_label_or_locale(data["language"]), 0).id,
      optin_time:
        if(String.length(data["opt_in"]) != 0,
          do: elem(Timex.parse(data["opt_in"], "{YYYY}-{0M}-{0D}"), 1),
          else: nil
        ),
      delete: data["delete"]
    }
  end

  @spec insert_or_update_contact_data(map(), non_neg_integer) :: Contact.t() | map()
  defp insert_or_update_contact_data(contact, group_id) do
    result =
      case contact.optin_time do
        nil -> GupshupContacts.create_or_update_contact(Map.put(contact, :method, "Import"))
        _ -> Contacts.optin_contact(Map.put(contact, :method, "Import"))
      end

    case result do
      {:ok, contact} ->
        Groups.create_contact_group(%{
          contact_id: contact.id,
          group_id: group_id,
          organization_id: contact.organization_id
        })

        contact

      {:error, error} ->
        %{phone: contact.phone, error: error}
    end
  end

  @spec delete_contact_data([map()]) :: [Contact.t()]
  defp delete_contact_data(contacts) do
    phone_nos_to_be_deleted = contacts |> Enum.map(fn contact -> contact.phone end)

    Contacts.fetch_contacts_in_phone_list(phone_nos_to_be_deleted)
    |> Enum.map(&Contacts.delete_contact/1)
  end

  @spec fetch_contact_data_as_string(Keyword.t()) :: %File.Stream{} | %IO.Stream{}
  defp fetch_contact_data_as_string(opts) do
    file_path = Keyword.get(opts, :file_path, nil)
    url = Keyword.get(opts, :url, nil)
    data = Keyword.get(opts, :data, nil)

    cond do
      file_path != nil ->
        file_path |> Path.expand() |> File.stream!()

      url != nil ->
        {_, response} = Tesla.get(url)
        {_, stream} = StringIO.open(response.body)
        stream |> IO.binstream(:line)

      data != nil ->
        {_, stream} = StringIO.open(data)
        stream |> IO.binstream(:line)
    end
  end

  @doc """
  This method allows importing of contacts to a particular organization and group

  The method takes in a csv file path and adds the contacts to the particular organization
  and group.
  """
  @spec import_contacts(integer, String.t(), []) :: tuple()
  def import_contacts(organization_id, group_label, opts \\ []) do
    if length(opts) > 1 do
      raise "Please specify only one of keyword arguments: file_path, url or data"
    end
    contact_data_as_stream = fetch_contact_data_as_string(opts)

    with %{id: organization_id} <- Partners.organization(organization_id),
         {_, group} <- Groups.get_or_create_group_by_label(group_label, organization_id) do
      contact_data =
        contact_data_as_stream
        |> CSV.decode(headers: true, strip_fields: true)
        |> Enum.map(fn {_, data} -> cleanup_contact_data(data, organization_id) end)

      contact_data |> Enum.filter(fn contact -> contact.delete == "1" end) |> delete_contact_data

      result =
        contact_data
        |> Enum.filter(fn contact -> contact.delete != "1" end)
        |> Enum.map(fn contact -> insert_or_update_contact_data(contact, group.id) end)

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
