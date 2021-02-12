defmodule Glific.Repo.Seeds.AddGlificData_v0_11_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Repo,
    Settings,
    Users.User,
  }

  @simulator_phone "9876543210"
  @tides_phone "1234567890"

  def up(_repo) do
    adding_simulators()
  end

  defp adding_simulators() do
    Partners.list_organizations()
    |> seed_contacts()
    |> seed_users()
  end

  @doc false
  @spec seed_contacts([Organization.t()]) :: [Organization.t()]
  def seed_contacts(organizations \\ []) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    simulators = [
      {"Two", "_2"},
      {"Three", "_3"},
      {"Four", "_4"},
      {"Five", "_5"}
    ]

    contact_entries =
      for org <- organizations,
          {name, phone} <- simulators do
        %{
          name: "Simulator " <> name,
          phone: @simulator_phone <> phone,
          organization_id: org.id,
          inserted_at: utc_now,
          updated_at: utc_now,
          last_message_at: utc_now,
          last_communication_at: utc_now,
          optin_time: utc_now,
          bsp_status: :session_and_hsm,
          language_id: en_us.id
        }
      end
      |> List.flatten()

    Repo.insert_all!(contact_entries)
  end

  @doc false
  @spec seed_users([Organization.t()]) :: [Organization.t()]
  def seed_users(organizations \\ []) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    for org <- organizations do
      attrs =
        %Contact{
          name: "Tides Admin"
          phone: @tides_phone,
          organization_id: org.id,
          inserted_at: utc_now,
          updated_at: utc_now,
          last_message_at: utc_now,
          last_communication_at: utc_now,
          optin_time: utc_now,
          bsp_status: :session_and_hsm,
          language_id: en_us.id
        }

      contact = Repo.insert!(attrs)

      password = Ecto.UUID.generate()
      attrs = %User{
        name: "Tides Admin",
        phone: @tides_phone,
        password: password,
        confirm_password: password,
        roles: ["admin"],
        contact_id: contact.id,
        organization_id: org.id
      }
      _user = Repo.insert!(attrs)
    end
end
