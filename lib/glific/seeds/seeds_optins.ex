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

  defp import_optin_contacts(organization, [contact_phone, _contact_name | _] = contact) do
    bsp_credentials = organization.services["bsp"]

    url =
      bsp_credentials.keys["api_end_point"] <>
        "/app/opt/in/" <> bsp_credentials.secrets["app_name"]

    api_key = bsp_credentials.secrets["api_key"]

    with {:ok, response} <-
           post(url, %{user: contact_phone}, headers: [{"apikey", api_key}]),
         true <- response.status == 202 do
      insert_opted_in_contacts(organization, contact)
    end
  end

  @spec insert_opted_in_contacts(map(), list()) :: :ok | any
  defp insert_opted_in_contacts(organization, [contact_phone] = _contact) do
    insert_opted_in_contacts(organization, [contact_phone, nil])
  end

  defp insert_opted_in_contacts(organization, [contact_phone, contact_name | _] = _contact) do
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

    # fetch and update contact details of optin time, last message at, bsp status
    {:ok, credential} =
      %{organization_id: organization.id, shortcode: "gupshup"}
      |> Partners.get_credential()

    Partners.fetch_opted_in_contacts(credential)
  end
end
