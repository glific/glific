defmodule Glific.Seeds.Simulator do
  @simulator_phone "9876543210"

  alias Glific.{Contacts.Contact, Repo}

  def add_more_simulators(org_ids) do
    simulators = [
      {"Two", "_2"},
      {"Three", "_3"},
      {"Four", "_4"},
      {"Five", "_5"},
    ]

    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    contact_entries =
    for org_id <- org_ids,
      {name, ext} <- simulators do
        %{
          name: "Simulator: " <> name,
          phone: @simulator_phone <> ext,
          inserted_at: utc_now,
          updated_at: utc_now,
          organization_id: org_id,
          last_message_at: utc_now,
          last_communication_at: utc_now,
          optin_time: utc_now,
          bsp_status: :session_and_hsm,
          language_id: 1
        }
    end

    # seed contacts
    Repo.insert_all(Contact, contact_entries)
  end

  @tides_phone "0123456789"
  def add_tides_user_contact(org_ids) do
    contact_entries =
    for org_id <- org_ids do
      %{
        name: "Tides Admin",
        phone: @tides_phone,
        inserted_at: utc_now,
        updated_at: utc_now,
        organization_id: org_id,
        last_message_at: utc_now,
        last_communication_at: utc_now,
        optin_time: utc_now,
        bsp_status: :session_and_hsm,
        language_id: 1
      }
    end

    # seeds contacts for users
    contact_ids = Repo.insert_all(Contact, contact_entries, returning: :id)

    # now create a user for each of the orgs given the contact id
    user_entries =
    for {org_id, contact_id} = zip(org_ids, contact_ids) do
      %{
        name: "Tides Admin",
        phone: @tides_phone,
        password: password,
        confirm_password: password,
        roles: roles,
        contact_id: contact.id,
        organization_id: organization.id
      }
    end
  end

  def run_update(org_ids \\ []) do
    org_ids = Enum.to_list(1..3) ++ [6] ++ Enum.to_list(19..15) ++ Enum.to_list(18..22)
  end

  def run_update(org_ids) do
    add_more_simulators(org_ids)

    add_tides_user_contact(org_ids)
  end

end
