defmodule Glific.Seeds.SeedsMigration do
  @moduledoc """
  One shot migration of data to add simulators and saas admin.
  We use the functions in this file to add simulators for new organizations as
  they are created
  """

  import Ecto.Query

  alias Glific.{
    Bigquery,
    Contacts,
    Contacts.Contact,
    Groups.Group,
    Partners,
    Partners.Organization,
    Repo,
    Searches.SavedSearch,
    Seeds.SeedsFlows,
    Seeds.SeedsStats,
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
      :collection ->
        seed_collections(organizations)

      :fix_message_number ->
        fix_message_number(organizations)

      :optin ->
        optin_data(organizations)

      :opt_in_out ->
        SeedsFlows.opt_in_out_flows(organizations)

      :simulator ->
        add_simulators(organizations)

      :stats ->
        org_id_list = Enum.map(organizations, fn o -> o.id end)
        SeedsStats.seed_stats(org_id_list)

      :sync_bigquery ->
        bigquery_enabled_org_ids()
        |> sync_schema_with_bigquery()

      :localized_language ->
        update_localized_language()

      :user_default_language ->
        update_user_default_language()
    end
  end

  @doc false
  @spec add_simulators(list()) :: :ok
  def add_simulators(organizations) do
    [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

    organizations
    |> seed_simulators(en)
    |> seed_users(en)

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
      last_message_at: DateTime.truncate(time, :second),
      last_communication_at: DateTime.truncate(time, :second),
      optin_time: DateTime.truncate(time, :second)
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

      utc_now = DateTime.utc_now()
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
      utc_now = DateTime.utc_now()

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

  @doc """
  Sync bigquery schema with local db changes.
  """
  @spec sync_schema_with_bigquery(list) :: :ok
  def sync_schema_with_bigquery(org_id_list),
    do: Enum.each(org_id_list, &Bigquery.sync_schema_with_bigquery(&1))

  @doc """
  Reset message number for a list of organizations or for a org_id
  """
  @spec fix_message_number(list | integer()) :: :ok
  def fix_message_number(org_id) when is_integer(org_id) do
    # set a large query timeout for this
    [
      fix_message_number_query_for_contacts(org_id),
      set_last_message_number_for_contacts(org_id),
      fix_message_number_query_for_groups(org_id),
      set_last_message_number_for_collection(org_id)
    ]
    |> Enum.each(&Repo.query!(&1, [], timeout: 900_000))

    :ok
  end

  def fix_message_number(organizations) when is_list(organizations),
    do: organizations |> Enum.each(fn org -> fix_message_number(org.id) end)

  @spec fix_message_number_query_for_contacts(integer()) :: String.t()
  defp fix_message_number_query_for_contacts(org_id) do
    """
    UPDATE
      messages m
      SET
        message_number = m2.row_num
      FROM (
        SELECT
          id,
          contact_id,
          ROW_NUMBER() OVER (PARTITION BY contact_id ORDER BY inserted_at ASC) AS row_num
        FROM
          messages m2
        WHERE
          m2.organization_id = #{org_id} and m2.sender_id != m2.receiver_id ) m2
      WHERE
        m.organization_id = #{org_id} and m.sender_id != m.receiver_id and m.id = m2.id;
    """
  end

  @spec fix_message_number_query_for_groups(integer()) :: String.t()
  defp fix_message_number_query_for_groups(org_id) do
    """
    UPDATE
      messages m
      SET
        message_number = m2.row_num
      FROM (
        SELECT
          id,
          group_id,
          ROW_NUMBER() OVER (PARTITION BY group_id ORDER BY inserted_at ASC) AS row_num
        FROM
          messages m2
        WHERE
          m2.organization_id = #{org_id} and m2.sender_id = m2.receiver_id ) m2
      WHERE
        m.organization_id = #{org_id} and m.sender_id = m.receiver_id and m.id = m2.id;
    """
  end

  @spec set_last_message_number_for_contacts(integer()) :: String.t()
  defp set_last_message_number_for_contacts(org_id) do
    """
    UPDATE
      contacts c
    SET
      last_message_number = (
        SELECT
          max(message_number) as message_number
        FROM
          messages
        WHERE
          contact_id = c.id)
      WHERE
        organization_id = #{org_id};
    """
  end

  @spec set_last_message_number_for_collection(integer()) :: String.t()
  defp set_last_message_number_for_collection(org_id) do
    """
    UPDATE
      groups g
    SET
      last_message_number = (
        SELECT
          max(message_number) as message_number
        FROM
          messages
        WHERE
          group_id = g.id and messages.receiver_id = messages.sender_id)
      WHERE
        organization_id = #{org_id};
    """
  end

  @spec bigquery_enabled_org_ids() :: list()
  defp bigquery_enabled_org_ids do
    Glific.Partners.Credential
    |> join(:left, [c], p in Glific.Partners.Provider, as: :p, on: c.provider_id == p.id)
    |> where([_c, p], p.shortcode == ^"bigquery")
    |> where([c, _p], c.is_active)
    |> select([c, _p], c.organization_id)
    |> Repo.all()
  end

  @spec update_localized_language() :: :ok
  defp update_localized_language() do
    Glific.Settings.Language
    |> where([l], l.label in ["English", "Hindi"])
    |> update([l], set: [localized: true])
    |> Repo.update_all([], skip_organization_id: true)
  end

  @spec update_user_default_language() :: :ok
  defp update_user_default_language() do
    {:ok, en} = Repo.fetch_by(Language, %{label_locale: "English"})

    Glific.Users.User
    |> update([u], set: [language_id: ^en.id])
    |> Repo.update_all([], skip_organization_id: true)
  end
end
