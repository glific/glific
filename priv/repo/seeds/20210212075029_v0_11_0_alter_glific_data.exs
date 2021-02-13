defmodule Glific.Repo.Seeds.AddGlificData_v0_11_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Repo,
    Settings,
    Users
  }

  def up(_repo) do
    adding_contacts()
  end

  defp adding_contacts() do
    Partners.active_organizations([])
    |> Enum.each(fn {org_id, _name} ->
      Glific.Repo.put_organization_id(org_id)
      seed_simulators(org_id)
      seed_user(org_id)
    end)
  end

  defp seed_simulators(org_id) do
    simulator_phone_prefix = Contacts.simulator_phone_prefix()

    simulators = [
      {"Two", "_2"},
      {"Three", "_3"},
      {"Four", "_4"},
      {"Five", "_5"}
    ]

    simulators
    |> Enum.each(fn {name, phone} ->
      attrs = %{
        name: "Simulator " <> name,
        phone: simulator_phone_prefix <> phone
      }

      create_contact(attrs, org_id)
    end)
  end

  defp seed_user(org_id) do
    tides_phone = Contacts.tides_phone()

    attrs = %{
      name: "Tides Admin",
      phone: tides_phone
    }

    with {:ok, contact} <- create_contact(attrs, org_id) do
      password = Ecto.UUID.generate()

      Users.create_user(%{
        name: "Tides Admin",
        phone: tides_phone,
        password: password,
        confirm_password: password,
        roles: ["admin"],
        contact_id: contact.id,
        organization_id: org_id
      })
    end
  end

  defp create_contact(attrs, org_id) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    contact =
      %{
        organization_id: org_id,
        inserted_at: utc_now,
        updated_at: utc_now,
        last_message_at: utc_now,
        last_communication_at: utc_now,
        optin_time: utc_now,
        bsp_status: :session_and_hsm,
        language_id: en_us.id
      }
      |> Map.merge(attrs)

    with nil <-
           Repo.get_by(Contact, %{
             phone: contact.phone,
             organization_id: org_id
           }) do
      Contacts.create_contact(contact)
    end
  end
end
