defmodule Glific.Seeds.SeedsOptins do
  @moduledoc """
    Script for importing optin contacts for an organization
  """
  use Tesla

  plug Tesla.Middleware.FormUrlencoded

  alias Glific.{
    Contacts,
    Partners
  }

  @spec import_optin_contacts(map(), list()) :: :ok | any
  defp import_optin_contacts(organization, [contact_phone] = _contact) do
    import_optin_contacts(organization, [contact_phone, nil])
  end

  defp import_optin_contacts(organization, [_contact_phone, _contact_name | _] = contact) do
    insert_opted_in_contact(organization, contact)
  end

  @spec insert_opted_in_contact(map(), list()) :: :ok | any
  defp insert_opted_in_contact(organization, [contact_phone] = _contact) do
    insert_opted_in_contact(organization, [contact_phone, nil])
  end

  defp insert_opted_in_contact(organization, [contact_phone, contact_name | _] = _contact) do
    Contacts.upsert(%{
      name: contact_name,
      phone: contact_phone,
      organization_id: organization.id,
      language_id: organization.default_language_id
    })
  end

  @spec process_csv_file(String.t()) :: list()
  defp process_csv_file(file) do
    file
    |> File.stream!()
    |> CSV.decode()
    |> Enum.map(fn {:ok, contact} -> contact end)
  end

  @doc """
  Import optin contacts from csv
  """
  @spec seed(String.t(), String.t()) :: any()
  def seed(shortcode, file) do
    organization = Partners.organization(shortcode)

    process_csv_file(file)
    |> Enum.each(fn contact ->
      # upsert contact with provided phone and name
      import_optin_contacts(organization, contact)
    end)
  end
end
