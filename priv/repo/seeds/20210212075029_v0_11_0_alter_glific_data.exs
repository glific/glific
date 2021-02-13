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
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    Partners.active_organizations([])
    |> Enum.each(fn {org_id, _name} ->
      Glific.Repo.put_organization_id(org_id)
      seed_simulators(org_id, utc_now, en_us.id)
      seed_user(org_id, utc_now, en_us.id)
    end)
  end

  defp seed_simulators(org_id, utc_now, language_id) do
    simulator_phone_prefix = Contacts.simulator_phone_prefix()

    simulators = [
      {"Two", "_2"},
      {"Three", "_3"},
      {"Four", "_4"},
      {"Five", "_5"}
    ]

    simulators
    |> Enum.each(fn {name, phone} ->
      simulator_contact = %{
        name: "Simulator " <> name,
        phone: simulator_phone_prefix <> phone,
        language_id: language_id,
        inserted_at: utc_now,
        updated_at: utc_now,
        organization_id: org_id,
        last_message_at: utc_now,
        last_communication_at: utc_now,
        optin_time: utc_now,
        bsp_status: :session_and_hsm
      }

      with nil <-
             Repo.get_by(Contact, %{
               phone: simulator_contact.phone,
               organization_id: simulator_contact.organization_id
             }) do
        Contacts.create_contact(simulator_contact)
      end
    end)
  end

  defp seed_user(org_id, utc_now, language_id) do
    tides_phone = Contacts.tides_phone()

    attrs = %{
      name: "Tides Admin",
      phone: tides_phone,
      organization_id: org_id,
      inserted_at: utc_now,
      updated_at: utc_now,
      last_message_at: utc_now,
      last_communication_at: utc_now,
      optin_time: utc_now,
      bsp_status: :session_and_hsm,
      language_id: language_id
    }

    with nil <-
           Repo.get_by(Contact, %{
             phone: tides_phone,
             organization_id: org_id
           }) do
      {:ok, contact} = Contacts.create_contact(attrs)
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
end
