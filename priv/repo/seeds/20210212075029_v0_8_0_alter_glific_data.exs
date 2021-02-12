defmodule Glific.Repo.Seeds.AddGlificData_v0_8_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Contacts.Contact,
    Partners.Provider,
    Partners.Credential,
    Settings,
    Repo
  }

  def up(_repo) do
    adding_simulators()
  end

  defp adding_simulators() do
    organizations = Repo.all(Organization, skip_organization_id: true)

    organizations |> Enum.each(fn organization -> seed_contacts(organization) end)
  end
  @doc false
  @spec seed_contacts(Organization.t() | nil) :: {integer(), nil}
  def seed_contacts(organization \\ nil) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    contacts = [
      %{
        name: "Simulator Two",
        phone: @simulator_phone <> "_2",
        language_id: en_us.id
      },
      %{
        name: "Simulator Three",
        phone: @simulator_phone <> "_3",
        language_id: en_us.id
      },
      %{
        name: "Simulator Four",
        phone: @simulator_phone <> "_4",
        language_id: en_us.id
      },
      %{
        name: "Simulator Five",
        phone: @simulator_phone <> "_5",
        language_id: en_us.id
      }
    ]

    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    contact_entries =
      for contact_entry <- contacts do
        %{
          inserted_at: utc_now,
          updated_at: utc_now,
          organization_id: organization.id,
          last_message_at: utc_now,
          last_communication_at: utc_now,
          bsp_status: :session
        }
        |> Map.merge(contact_entry)
      end

    # seed contacts
    Repo.insert_all(Contact, contact_entries)
  end
end
