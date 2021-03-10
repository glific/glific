defmodule Glific.Seeds.SeedsMigration do
  @moduledoc """
  One shot migration of data to add simulators and saas admin.
  We use the functions in this file to add simulators for new organizations as
  they are created
  """

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Groups.Group,
    Partners,
    Partners.Organization,
    Repo,
    Searches.SavedSearch,
    Seeds.SeedsFlows,
    Settings,
    Settings.Language,
    Users,
    Users.User
  }

  @doc """
  Public interface to do a seed migration across all organizations.

  One function to rule them all. This function is invoked manually by a glific developer
  to add data from the DB. This seems the cleanest way to do such things. We use phases to
  seperate different migrations
  """
  @spec migrate_data(atom(), Organization.t() | nil) :: :ok
  def migrate_data(phase, organization \\ nil) do
    organizations =
      if is_nil(organization),
        do: Partners.list_organizations(),
        else: [organization]

    case phase do
      :simulator -> add_simulators(organizations)
      :optin -> optin_data(organizations)
      :collection -> seed_collections(organizations)
      :opt_in_out -> SeedsFlows.opt_in_out_flows(organizations)
    end
  end

  @doc false
  @spec add_simulators(list()) :: :ok
  def add_simulators(organizations) do
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
  @spec seed_collections([Organization.t()]) :: [Organization.t()]
  defp seed_collections(organizations) do
    for org <- organizations,
        do: create_collections(org)

    organizations
  end

  defp create_collections(organization) do
    Repo.insert!(%Group{
      label: "Optin contacts",
      is_restricted: false,
      organization_id: organization.id
    })

    Repo.insert!(%Group{
      label: "Optout contacts",
      is_restricted: false,
      organization_id: organization.id
    })
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

    organizations
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

  @spec optin_data(list()) :: :ok
  defp optin_data(organizations) do
    add_optin_search(organizations)

    migrate_optin_data()
  end

  @spec add_optin_search(list()) :: :ok
  defp add_optin_search(organizations) do
    shortcode = "Optin"

    organizations
    |> Enum.each(fn org ->
      Repo.insert!(%SavedSearch{
        label: "Conversations where the contact has opted in",
        shortcode: shortcode,
        args: %{
          filter: %{status: shortcode, term: ""},
          contactOpts: %{limit: 25, offset: 0},
          messageOpts: %{limit: 20, offset: 0}
        },
        is_reserved: true,
        organization_id: org.id
      })
    end)
  end

  @spec migrate_optin_data :: :ok
  defp migrate_optin_data do
    # Set false status for contacts not opted in
    Contact
    |> where([c], is_nil(c.optin_time))
    |> update([c], set: [optin_status: false])
    |> Repo.update_all([], skip_organization_id: true)

    # Set true status where we have an optin_date,
    # also set method as BSP since they opted in via Gupshup
    Contact
    |> where([c], not is_nil(c.optin_time))
    |> update([c], set: [optin_status: true, optin_method: "BSP"])
    |> Repo.update_all([], skip_organization_id: true)

    :ok
  end
end
