defmodule Glific.Seeds.SeedsMigration do
  @moduledoc """
  One shot migration of data to add simulators and saas admin.
  We use the functions in this file to add simulators for new organizations as
  they are created
  """

  import Ecto.Query

  alias Glific.{
    AccessControl.Role,
    BigQuery,
    Contacts,
    Contacts.Contact,
    Flows,
    Groups.Group,
    Partners,
    Partners.Organization,
    Partners.Saas,
    Providers.Gupshup.ApiClient,
    Repo,
    Searches.SavedSearch,
    Seeds.SeedsDev,
    Seeds.SeedsFlows,
    Seeds.SeedsStats,
    Settings,
    Settings.Language,
    Templates,
    Templates.SessionTemplate,
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
    organizations = get_organizations(organization)

    do_migrate_data(phase, organizations)
  end

  @doc false
  @spec get_organizations(nil | Organization.t()) :: [Organization.t()]
  defp get_organizations(nil), do: Partners.list_organizations()
  defp get_organizations(organization), do: [organization]

  @doc false
  @spec do_migrate_data(atom(), [Organization.t()]) :: any()
  defp do_migrate_data(:collection, organizations), do: seed_collections(organizations)
  defp do_migrate_data(:fix_message_number, organizations), do: fix_message_number(organizations)
  defp do_migrate_data(:optin, organizations), do: optin_data(organizations)
  defp do_migrate_data(:opt_in_out, organizations), do: SeedsFlows.opt_in_out_flows(organizations)
  defp do_migrate_data(:simulator, organizations), do: add_simulators(organizations)

  defp do_migrate_data(:stats, organizations) do
    org_id_list = Enum.map(organizations, fn o -> o.id end)
    SeedsStats.seed_stats(org_id_list)
  end

  defp do_migrate_data(:sync_bigquery, _organizations) do
    bigquery_enabled_org_ids()
    |> sync_schema_with_bigquery()
  end

  defp do_migrate_data(:sync_hsm_templates, organizations),
    do:
      Enum.map(organizations, fn o -> o.id end)
      |> sync_hsm_templates()

  defp do_migrate_data(:localized_language, _organizations), do: update_localized_language()
  defp do_migrate_data(:user_default_language, _organizations), do: update_user_default_language()

  defp do_migrate_data(:submit_common_otp_template, organizations),
    do: Enum.map(organizations, fn org -> submit_otp_template_for_org(org.id) end)

  defp do_migrate_data(:set_newcontact_flow_id, organizations),
    do: Enum.map(organizations, fn org -> set_newcontact_flow_id(org.id) end)

  defp do_migrate_data(:set_default_organization_roles, organizations),
    do: Enum.map(organizations, fn org -> set_default_organization_roles(org.id) end)

  @doc false
  @spec add_simulators(list()) :: :ok
  def add_simulators(organizations) do
    [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

    organizations
    |> seed_simulators(en)
    |> seed_users(en)

    :ok
  end

  @doc """
  Create default organization roles for an organization
  """
  @spec set_default_organization_roles(non_neg_integer()) :: Role.t()
  def set_default_organization_roles(org_id) do
    org_id
    |> Partners.get_organization!()
    |> SeedsDev.seed_roles()
  end

  @doc false
  @spec submit_otp_template_for_org(any) ::
          {:error, Ecto.Changeset.t()} | {:ok, Templates.SessionTemplate.t()}
  def submit_otp_template_for_org(org_id) do
    %{
      is_hsm: true,
      shortcode: "common_otp",
      label: "common_otp",
      body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
      type: :text,
      category: "OTP",
      example: "Your OTP for [adding Anil as a payee] is [1234]. This is valid for [15 minutes].",
      is_active: true,
      is_source: false,
      language_id: 1,
      organization_id: org_id
    }
    |> Templates.create_session_template()
  end

  @doc false
  @spec set_newcontact_flow_id(non_neg_integer()) ::
          {:error, Ecto.Changeset.t()} | {:ok, Organization.t()}
  def set_newcontact_flow_id(org_id) do
    flow_id =
      org_id
      |> Flows.flow_keywords_map()
      |> Map.get("published")
      |> Map.get("newcontact", nil)

    org_id
    |> Partners.get_organization!()
    |> Partners.update_organization(%{newcontact_flow_id: flow_id})
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
          phone: Saas.phone(),
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
  sync all the hsm from BSP to Glific DB
  """
  @spec sync_hsm_templates(list) :: :ok
  def sync_hsm_templates(org_id_list) do
    Enum.each(org_id_list, fn org_id ->
      Repo.put_process_state(org_id)
      Glific.Templates.sync_hsms_from_bsp(org_id)
    end)

    :ok
  end

  @doc """
  Sync bigquery schema with local db changes.
  """
  @spec sync_schema_with_bigquery(list) :: :ok
  def sync_schema_with_bigquery(org_id_list),
    do: Enum.each(org_id_list, &BigQuery.sync_schema_with_bigquery(&1))

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
    Partners.Credential
    |> join(:left, [c], p in Partners.Provider, as: :p, on: c.provider_id == p.id)
    |> where([_c, p], p.shortcode == ^"bigquery")
    |> where([c, _p], c.is_active)
    |> select([c, _p], c.organization_id)
    |> Repo.all(skip_organization_id: true)
  end

  @spec update_localized_language() :: :ok
  defp update_localized_language do
    Settings.Language
    |> where([l], l.locale in ["en", "hi"])
    |> update([l], set: [localized: true])
    |> Repo.update_all([])
  end

  @spec update_user_default_language() :: :ok
  defp update_user_default_language do
    {:ok, en} = Repo.fetch_by(Language, %{label_locale: "English"})

    Glific.Users.User
    |> update([u], set: [language_id: ^en.id])
    |> Repo.update_all([], skip_organization_id: true)
  end

  @doc """
    We need this functionality to cleanups all the Approved templates which are not active on Gupshup
  """
  @spec get_deleted_hsms(non_neg_integer()) :: tuple()
  def get_deleted_hsms(org_id) do
    ApiClient.get_templates(org_id)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, response_data} = Jason.decode(body)
        hsms = response_data["templates"]
        uuid_list = Enum.map(hsms, fn hsm -> hsm["id"] end)

        corrupted_list =
          from(template in SessionTemplate)
          |> where([c], c.organization_id == ^org_id)
          |> where([c], c.uuid not in ^uuid_list)
          |> where([c], c.is_hsm == true)
          |> where([c], c.status in ["APPROVED", "SANDBOX_REQUESTED"])
          |> select([c], c.id)
          |> Repo.delete_all(skip_organization_id: true)

        {:ok, Enum.count(corrupted_list), corrupted_list}

      _ ->
        {:error, 0, "Could not fecth the data for org: #{org_id}"}
    end
  end
end
