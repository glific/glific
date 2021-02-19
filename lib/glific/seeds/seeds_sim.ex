defmodule Glific.Seeds.SeedsSim do
  @moduledoc """
  One shot migration of data to add simulators and saas admin.
  We use the functions in this file to add simulators for new organizations as
  they are created
  """

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Repo,
    Settings,
    Settings.Language,
    Users,
    Users.User
  }

  @doc """
  One function to rule them all. This function is invoked manually by a glific developer
  to add data from the DB. This seems the cleanest way to do such things
  """
  @spec add_simulators(Organization.t() | nil) :: :ok
  def add_simulators(organization \\ nil) do
    organizations =
      if is_nil(organization),
        do: Partners.list_organizations(),
        else: [organization]

    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    organizations
    |> seed_simulators(en_us)
    |> seed_users(en_us)

    :ok
  end

  @spec has_contact?(Organization.t(), String.t()) :: boolean
  defp has_contact?(organization, name) do
    case Repo.fetch_by(
           Contact,
           %{name: name, organization_id: organization.id},
           skip_organization_id: true
         ) do
      {:ok, _contact} -> true
      _ -> false
    end
  end

  @spec get_common_attrs(Organization.t(), Language.t(), DateTime.t()) :: map()
  defp get_common_attrs(organization, language, time) do
    %{
      organization_id: organization.id,
      language_id: language.id,
      bsp_status: :session_and_hsm,
      inserted_at: time,
      updated_at: time,
      last_message_at: time,
      last_communication_at: time,
      optin_time: time
    }
  end

  @doc false
  @spec seed_simulators([Organization.t()], Language.t()) :: [Organization.t()]
  def seed_simulators(organizations \\ [], language) do
    # for the insert's, lets precompute some values

    for org <- organizations do
      create_simulators(org, language)
    end

    organizations
  end

  @spec delete_old_simulators(Organization.t(), String.t()) :: :ok
  defp delete_old_simulators(organization, prefix) do
    Contact
    |> where([c], c.organization_id == ^organization.id)
    |> where([c], ilike(c.phone, ^"#{prefix}%"))
    |> Repo.delete_all()

    :ok
  end

  defp create_simulators(organization, language) do
    if !has_contact?(organization, "Glific Simulator Five") do
      simulators = [
        {"One", "_1"},
        {"Two", "_2"},
        {"Three", "_3"},
        {"Four", "_4"},
        {"Five", "_5"}
      ]

      utc_now = DateTime.utc_now() |> DateTime.truncate(:second)
      simulator_phone_prefix = Contacts.simulator_phone_prefix()

      # lets delete any old simulators for this organization
      delete_old_simulators(organization, simulator_phone_prefix)

      attrs = get_common_attrs(organization, language, utc_now)

      simulators =
        for {name, phone} <- simulators do
          Map.merge(
            attrs,
            %{
              name: "Glific Simulator " <> name,
              phone: simulator_phone_prefix <> phone
            }
          )
        end

      Repo.insert_all(Contact, simulators)
    end

    :ok
  end

  @doc false
  @spec seed_users([Organization.t()], Language.t()) :: [Organization.t()]
  def seed_users(organizations, language) do
    for org <- organizations do
      add_saas_user(org, language)
    end
  end

  @doc """
  Add a saas user for the organization. We need to check if it already exists
  since this code is used during data migration and can be repeated for the same
  organization
  """
  @spec add_saas_user(Organization.t(), Language.t()) :: :ok
  def add_saas_user(organization, language) do
    name = "SaaS Admin"

    if !has_contact?(organization, name) do
      # lets precompute common values
      utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

      organization
      |> get_common_attrs(language, utc_now)
      |> create_saas_contact(name)
      |> create_saas_user()
    end

    :ok
  end

  @spec create_saas_contact(map(), String.t()) :: Contact.t()
  defp create_saas_contact(attrs, name) do
    attrs =
      Map.merge(
        attrs,
        %{
          phone: Contacts.saas_phone(),
          name: name
        }
      )

    Contact
    |> struct(attrs)
    |> Repo.insert!()
  end

  @spec create_saas_user(Contact.t()) :: User.t()
  defp create_saas_user(contact) do
    password = Ecto.UUID.generate()

    {:ok, user} =
      Users.create_user(%{
        name: contact.name,
        phone: contact.phone,
        password: password,
        confirm_password: password,
        roles: ["admin"],
        contact_id: contact.id,
        organization_id: contact.organization_id
      })

    user
  end
end
