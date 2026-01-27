defmodule Glific.Partners do
  @moduledoc """
  The Partners context. This is the gateway for the application to access/update all the organization
  and Provider information.
  """
  use Publicist

  import Ecto.Query, warn: false
  use Gettext, backend: GlificWeb.Gettext
  require Logger

  alias __MODULE__

  alias Glific.{
    BigQuery,
    Caches,
    Contacts,
    Contacts.Contact,
    Flags,
    Flows,
    Flows.Flow,
    GCS,
    Mails.GupshupSetupMail,
    Notifications,
    Partners.Credential,
    Partners.Organization,
    Partners.OrganizationData,
    Partners.Provider,
    Providers.Gupshup.GupshupWallet,
    Providers.Gupshup.PartnerAPI,
    Providers.Maytapi.WAWorker,
    Repo,
    RepoReplica,
    Settings.Language,
    Stats,
    Users.User
  }

  # We cache organization info under this id since when we want to retrieve
  # by shortcode we do not have an organization id to retrieve it from.
  @global_organization_id 0

  @doc """
  Returns the list of providers.

  ## Examples

      iex> list_providers()
      [%Provider{}, ...]

  """
  @spec list_providers(map()) :: [Provider.t(), ...]
  def list_providers(args \\ %{}) do
    Repo.list_filter(args, Provider, &Repo.opts_with_name/2, &filter_provider_with/2)
    |> Enum.reject(fn provider ->
      Enum.member?(
        [
          "goth",
          "kaapi",
          "gupshup_enterprise",
          "navana_tech",
          "google_asr",
          "dialogflow",
          "open_ai"
        ],
        provider.shortcode
      )
    end)
  end

  @doc """
  Return the count of providers, using the same filter as list_providers
  """
  @spec count_providers(map()) :: integer
  def count_providers(args \\ %{}),
    do: list_providers(args) |> length()

  @spec filter_provider_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_provider_with(query, filter) do
    filter = Map.delete(filter, :organization_id)
    Repo.filter_with(query, filter)
  end

  @doc """
  Gets a single provider.

  Raises `Ecto.NoResultsError` if the Provider does not exist.

  ## Examples

      iex> get_provider!(123)
      %Provider{}

      iex> get_provider!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_provider!(id :: integer) :: Provider.t()
  def get_provider!(id), do: Repo.get!(Provider, id)

  @doc """
  Creates a provider.

  ## Examples

      iex> create_provider(%{field: value})
      {:ok, %Provider{}}

      iex> create_provider(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_provider(map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def create_provider(attrs \\ %{}) do
    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a provider.

  ## Examples

      iex> update_provider(provider, %{field: new_value})
      {:ok, %Provider{}}

      iex> update_provider(provider, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_provider(Provider.t(), map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def update_provider(%Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a provider.

  ## Examples

      iex> delete_provider(provider)
      {:ok, %Provider{}}

      iex> delete_provider(provider)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_provider(Provider.t()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def delete_provider(%Provider{} = provider) do
    provider
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:organizations, name: "organizations_provider_id_fkey")
    |> Ecto.Changeset.no_assoc_constraint(:credential)
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking provider changes.

  ## Examples

  iex> change_provider(provider)
  %Ecto.Changeset{data: %Provider{}}
  """
  @spec change_provider(Provider.t(), map()) :: Ecto.Changeset.t()
  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  @doc """
  Returns the list of organizations.

  ## Examples

      iex> Glific.Partners.list_organizations()
      [%Glific.Partners.Organization{}, ...]

  """
  @spec list_organizations(map()) :: [Organization.t()]
  def list_organizations(args \\ %{}),
    do:
      Repo.list_filter(
        args,
        Organization,
        &Repo.opts_with_name/2,
        &filter_organization_with/2,
        skip_organization_id: true
      )

  @doc """
  List of organizations that are active within the system
  """
  @spec active_organizations(list(), boolean) :: map()
  def active_organizations(orgs, suspended \\ false) do
    Organization
    |> where([q], q.is_active == true)
    |> select([q], [q.id, q.name, q.last_communication_at])
    |> where([q], q.is_suspended == ^suspended)
    |> restrict_orgs(orgs)
    |> Repo.all(skip_organization_id: true)
    |> Enum.reduce(%{}, fn row, acc ->
      [id, value, time] = row
      Map.put(acc, id, %{name: value, last_communication_at: time})
    end)
  end

  @spec restrict_orgs(Ecto.Query.t(), list()) :: Ecto.Query.t()
  defp restrict_orgs(query, []), do: query

  defp restrict_orgs(query, org_list),
    do: query |> where([q], q.id in ^org_list)

  @doc """
  Return the count of organizations, using the same filter as list_organizations
  """
  @spec count_organizations(map()) :: integer
  def count_organizations(args \\ %{}),
    do:
      Repo.count_filter(
        args,
        Organization,
        &filter_organization_with/2,
        skip_organization_id: true
      )

  # codebeat:disable[ABC]
  @spec filter_organization_with(Ecto.Queryable.t(), %{optional(atom()) => any}) ::
          Ecto.Queryable.t()
  defp filter_organization_with(query, filter) do
    filter = Map.delete(filter, :organization_id)
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:email, email}, query ->
        from(q in query, where: ilike(q.email, ^"%#{email}%"))

      {:bsp, bsp}, query ->
        from(q in query,
          join: c in assoc(q, :bsp),
          where: ilike(c.name, ^"%#{bsp}%")
        )

      {:default_language, default_language}, query ->
        from(q in query,
          join: c in assoc(q, :default_language),
          where: ilike(c.label, ^"%#{default_language}%")
        )

      _, query ->
        query
    end)
  end

  # codebeat:enable[ABC]

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the organization does not exist.

  ## Examples

  iex> Glific.Partners.get_organization!(1)
  %Glific.Partners.Organization{}

  iex> Glific.Partners.get_organization!(-1)
  ** (Ecto.NoResultsError)
  """
  @spec get_organization!(integer) :: Organization.t()
  def get_organization!(id), do: Repo.get!(Organization, id, skip_organization_id: true)

  @doc """
  Creates a organization.

  ## Examples

      iex> Glific.Partners.create_organization(%{name: value})
      {:ok, %Glific.Partners.Organization{}}

      iex> Glific.Partners.create_organization(%{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_organization(map()) :: {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert(skip_organization_id: true)
  end

  @doc """
  Updates an organization.

  ## Examples

      iex> Glific.Partners.update_organization(Organization, %{name: new_name})
      {:ok, %Glific.Partners.Organization{}}

      iex> Glific.Partners.update_organization(Organization, %{abc: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_organization(Organization.t(), map()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def update_organization(%Organization{} = organization, %{phone: phone} = attrs)
      when phone != nil do
    with {:ok, phone} <- Contacts.parse_phone_number(phone),
         {:ok, %{organization: updated_org}} <-
           update_org_contact_and_user(organization, phone, attrs) do
      {:ok, updated_org}
    else
      {:error, _step, reason, _changes_so_far} ->
        Glific.Metrics.increment("Org Phone Number Update Failed")
        {:error, reason}

      {:error, message} ->
        Glific.Metrics.increment("Org Phone Number Update Failed")
        {:error, message}
    end
  end

  def update_organization(%Organization{} = organization, attrs) do
    do_update_org(organization, attrs)
  end

  @spec update_org_contact_and_user(Organization.t(), String.t(), map()) ::
          {:ok, %{contact: any(), user: any(), organization: any()}}
          | {:error, atom(), any(), any()}
  defp update_org_contact_and_user(organization, phone, attrs) do
    setting_map =
      (organization.setting || %{})
      |> Map.from_struct()
      |> Map.put(:allow_bot_number_update, false)

    attrs = Map.put(attrs, :setting, setting_map)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:contact, fn _repo, _changes ->
      update_org_contact(organization, phone)
    end)
    |> Ecto.Multi.run(:user, fn _repo, _changes ->
      update_main_user(organization, phone)
    end)
    |> Ecto.Multi.run(:organization, fn _repo, _changes ->
      do_update_org(organization, attrs)
    end)
    |> Repo.transaction()
  end

  @spec update_main_user(Organization.t(), String.t()) :: {:ok, User.t()} | {:error, String.t()}
  defp update_main_user(org, phone) do
    case Repo.fetch_by(User, %{organization_id: org.id, contact_id: org.contact_id}) do
      {:ok, user} ->
        user
        |> Ecto.Changeset.change(%{phone: phone})
        |> Repo.update()

      _ ->
        {:error, "NGO Main Account not found"}
    end
  end

  @spec do_update_org(Organization.t(), map()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  defp do_update_org(%Organization{} = organization, attrs) do
    # first delete the cached organization
    remove_organization_cache(organization.id, organization.shortcode)

    ## in case user updates the out of office flow it should update the flow keyword map as well.
    ## We need to think about a better approach to handle this one.
    Caches.remove(organization.id, ["flow_keywords_map"])

    with {:ok, updated_organization} <-
           organization
           |> Organization.changeset(attrs)
           |> Repo.update(skip_organization_id: true) do
      # pin both new contact and optin flow id
      maybe_pin_flow(
        updated_organization.newcontact_flow_id,
        organization.newcontact_flow_id,
        updated_organization
      )

      maybe_pin_flow(
        updated_organization.optin_flow_id,
        organization.optin_flow_id,
        updated_organization
      )
    end
  end

  @spec update_org_contact(Organization.t(), String.t()) ::
          {:ok, Contact.t()} | {:error, String.t()}
  defp update_org_contact(org, phone) do
    case Repo.fetch(Contact, org.contact_id) do
      {:ok, contact} ->
        contact
        |> Contact.changeset(%{phone: phone})
        |> Repo.update()

      _ ->
        {:error, "Organization contact not found"}
    end
  end

  @spec maybe_pin_flow(non_neg_integer(), non_neg_integer(), Organization.t()) ::
          {:ok, Organization.t()}
  defp maybe_pin_flow(nil, old_flow_id, organization) do
    pin_flow(old_flow_id, false)
    {:ok, organization}
  end

  defp maybe_pin_flow(flow_id, nil, organization) do
    pin_flow(flow_id, true)
    {:ok, organization}
  end

  defp maybe_pin_flow(flow_id, old_flow_id, organization)
       when flow_id != old_flow_id do
    pin_flow(old_flow_id, false)
    pin_flow(flow_id, true)
    {:ok, organization}
  end

  defp maybe_pin_flow(_flow_id, _old_flow_id, organization),
    do: {:ok, organization}

  @spec pin_flow(non_neg_integer(), boolean()) ::
          {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  defp pin_flow(flow_id, pin_value) do
    with false <- is_nil(flow_id),
         {:ok, flow} <- Flows.fetch_flow(flow_id) do
      Flows.update_flow(flow, %{is_pinned: pin_value})
    end
  end

  @doc """
  Deletes an Organization.

  ## Examples

      iex> Glific.Partners.delete_organization(organization)
      {:ok, %Glific.Partners.Organization{}}

      iex> delete_organization(organization)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_organization(Organization.t()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def delete_organization(%Organization{} = organization) do
    # we are deleting an organization that is one of the SaaS users, not the current users org
    # setting timeout as the deleting organization is an expensive operation
    Repo.delete(organization, skip_organization_id: true, timeout: 900_000)
  end

  @doc """
  Deletes all the dynamic data for an organization. This includes all messages
  and contacts that are not users.any()

  This allows an organization to reset all its experiment data before going live.
  A feature to add in the future, might to be mark test contact with a "test" contact
  field and we'll delete only those contacts
  """
  @spec delete_organization_test_data(Organization.t()) :: {:ok, Organization.t()}
  def delete_organization_test_data(organization) do
    [
      "DELETE FROM messages WHERE organization_id = #{organization.id}",
      """
      DELETE FROM contacts WHERE
        organization_id = #{organization.id}
        AND (id NOT IN
          (SELECT c.id FROM contacts c
            LEFT JOIN  users ON users.contact_id = c.id
            WHERE c.organization_id = #{organization.id} AND users.id IS NOT NULL))
        AND id != #{organization.contact_id}
      """
    ]
    |> Enum.each(&Repo.query!(&1, [], timeout: 300_000, skip_organization_id: true))

    {:ok, organization}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking organization changes.

  ## Examples

      iex> Glific.Partners.change_organization(organization)
      %Ecto.Changeset{data: %Glific.Partners.Organization{}}

  """
  @spec change_organization(Organization.t(), map()) :: Ecto.Changeset.t()
  def change_organization(%Organization{} = organization, attrs \\ %{}) do
    Organization.changeset(organization, attrs)
  end

  @doc """
  Returns bsp balance for an organization
  """
  @spec get_bsp_balance(non_neg_integer) :: {:ok, any()} | {:error, String.t()}
  def get_bsp_balance(organization_id) do
    organization = organization(organization_id)

    if is_nil(organization.services["bsp"]) do
      {:error, dgettext("errors", "No active BSP available")}
    else
      case organization.bsp.shortcode do
        "gupshup" -> GupshupWallet.balance(organization_id)
        _ -> {:error, dgettext("errors", "Invalid BSP provider")}
      end
    end
  end

  @doc """
  Returns quality rating information for an organization provider
  """
  @spec get_quality_rating(non_neg_integer()) :: {:ok, any()} | {:error, String.t()}
  def get_quality_rating(organization_id) do
    organization = organization(organization_id)

    if is_nil(organization.services["bsp"]) do
      {:error, dgettext("errors", "No active BSP available")}
    else
      case organization.bsp.shortcode do
        "gupshup" -> PartnerAPI.get_quality_rating(organization_id)
        _ -> {:error, dgettext("errors", "Invalid BSP provider")}
      end
    end
  end

  @doc """
  Given a minimal organization object, fill it up and store in cache. Making this
  public so we can call from test harness and avoid SQL Sandbox issues
  """
  @spec fill_cache(Organization.t()) :: Organization.t()
  def fill_cache(organization) do
    # For this process, lets set the organization id
    Repo.put_organization_id(organization.id)

    organization =
      organization
      |> set_root_user()
      |> set_credentials()
      |> Repo.preload([:bsp, :contact])
      |> set_bsp_info()
      |> set_out_of_office_values()
      |> Flags.set_out_of_office()
      |> set_languages()
      |> Flags.set_flow_uuid_display()
      |> Flags.set_roles_and_permission()
      |> Flags.set_open_ai_auto_translation_enabled()
      |> Flags.set_auto_translation_enabled_for_google_trans()
      |> Flags.set_contact_profile_enabled()
      |> Flags.set_whatsapp_group_enabled()
      |> Flags.set_ticketing_enabled()
      |> Flags.set_certificate_enabled()
      |> Flags.set_interactive_re_response_enabled()
      |> Flags.set_is_kaapi_enabled()
      |> Flags.set_is_ask_me_bot_enabled()
      |> Flags.set_is_whatsapp_forms_enabled()
      |> Flags.set_flag_enabled(:high_trigger_tps_enabled)
      |> Flags.set_flag_enabled(:unified_api_enabled)

    Caches.set(
      @global_organization_id,
      [{:organization, organization.id}, {:organization, organization.shortcode}],
      organization
    )

    # also update the flags table with updated values
    Flags.init(organization)
    organization
  end

  @doc """
  Follow the cachex protocol to load the cache from the DB
  """
  @spec load_cache(tuple()) :: {:ignore, Organization.t()}
  def load_cache(cachex_key) do
    # this is of the form {:global_org_key, {:organization, value}}
    # we want the value element
    cache_key = cachex_key |> elem(1) |> elem(1)
    Logger.info("Loading organization cache: #{cache_key}")

    organization =
      if is_integer(cache_key) do
        get_organization!(cache_key) |> fill_cache()
      else
        case Repo.fetch_by(Organization, %{shortcode: cache_key}, skip_organization_id: true) do
          {:ok, organization} ->
            organization |> fill_cache()

          _ ->
            raise(ArgumentError, message: "Could not find an organization with #{cache_key}")
        end
      end

    # we are already storing this in the cache (in the function fill_cache),
    # so we can ask cachex to ignore the value. We need to do this since we are
    # storing multiple keys for the same object
    {:ignore, organization}
  end

  @doc """
  Cache the entire organization structure.
  """
  @spec organization(non_neg_integer | String.t()) ::
          Organization.t() | nil | {:error, String.t()}
  def organization(cache_key) do
    case Caches.fetch(@global_organization_id, {:organization, cache_key}, &load_cache/1) do
      {:error, error} ->
        {:error, error}

      {_, organization} ->
        Repo.put_organization_id(organization.id)
        organization
    end
  end

  @doc """
  This contact id is special since it is the sender for all outbound messages
  and the receiver for all inbound messages
  """
  @spec organization_contact_id(non_neg_integer) :: integer()
  def organization_contact_id(organization_id),
    do: organization(organization_id).contact_id

  @doc """
  Get the default language id
  """
  @spec organization_language_id(non_neg_integer) :: integer()
  def organization_language_id(organization_id),
    do: organization(organization_id).default_language_id

  @doc """
  Get the timezone
  """
  @spec organization_timezone(non_neg_integer) :: String.t()
  def organization_timezone(organization_id),
    do: organization(organization_id).timezone

  @spec set_root_user(Organization.t()) :: Organization.t()
  defp set_root_user(organization) do
    {:ok, root_user} = Repo.fetch_by(User, %{contact_id: organization.contact_id})
    Map.put(organization, :root_user, root_user)
  end

  @spec set_out_of_office_values(Organization.t()) :: Organization.t()
  defp set_out_of_office_values(organization) do
    out_of_office = organization.out_of_office

    {hours, days} =
      if out_of_office.enabled do
        hours = [out_of_office.start_time, out_of_office.end_time]

        days =
          Enum.reduce(
            out_of_office.enabled_days,
            [],
            fn x, acc ->
              if x.enabled,
                do: [x.id | acc],
                else: acc
            end
          )
          |> Enum.reverse()

        {hours, days}
      else
        {[], []}
      end

    organization
    |> Map.put(:hours, hours)
    |> Map.put(:days, days)
  end

  @spec set_languages(map()) :: map()
  defp set_languages(organization) do
    languages =
      Language
      |> where([l], l.id in ^organization.active_language_ids)
      |> Repo.all()

    organization
    |> Map.put(:languages, languages)
  end

  # Lets cache all bsp provider specific info in the organization entity since
  # we use it on all sending / receiving of messages
  @spec set_bsp_info(map()) :: map()
  defp set_bsp_info(organization) do
    bsp_credential = organization.services[organization.bsp.shortcode]

    updated_services_map =
      Map.merge(organization.services, %{
        "bsp" => bsp_credential
      })

    %{organization | services: updated_services_map}
  end

  # Lets cache keys and secrets of all the active services
  @spec set_credentials(map()) :: map()
  defp set_credentials(organization) do
    credentials =
      Credential
      |> where([c], c.organization_id == ^organization.id)
      |> where([c], c.is_active == true)
      |> preload(:provider)
      |> Repo.all()

    services_map =
      Enum.reduce(credentials, %{}, fn credential, acc ->
        Map.merge(acc, %{
          credential.provider.shortcode => %{keys: credential.keys, secrets: credential.secrets}
        })
      end)

    organization
    |> Map.put(:services, services_map)
  end

  @spec suspend_offset(Organization.t(), non_neg_integer()) :: DateTime.t()
  defp suspend_offset(org, 0), do: start_of_next_day(org)

  defp suspend_offset(_org, hours), do: Timex.shift(DateTime.utc_now(), hours: hours)

  # get the start of the next day in orgs timezone and then convert that to UTC since
  # we only store UTC time in our DB
  @spec start_of_next_day(Organization.t()) :: DateTime.t()
  defp start_of_next_day(org),
    do:
      org.timezone
      |> DateTime.now!()
      |> Timex.beginning_of_day()
      |> Timex.shift(days: 1)
      |> Timex.to_datetime("Etc/UTC")

  @doc """
  Suspend an organization till the start of the next day for the organization
  (we still need to figure out if this is the right WABA interpretation)
  """
  @spec suspend_organization(Organization.t(), non_neg_integer()) :: any()
  def suspend_organization(organization, hours \\ 0) do
    {:ok, _} =
      organization
      |> then(fn org ->
        Partners.update_organization(
          org,
          %{
            is_suspended: true,
            suspended_until: suspend_offset(org, hours)
          }
        )
      end)
  end

  @spec unsuspend_org_list(DateTime.t()) :: list()
  defp unsuspend_org_list(time \\ DateTime.utc_now()) do
    Organization
    |> where([q], q.is_active == true)
    |> select([q], q.id)
    |> where([q], q.is_suspended == true)
    |> where([q], q.suspended_until < ^time)
    |> Repo.all(skip_organization_id: true)
  end

  @spec unsuspend_organization(non_neg_integer()) :: any()
  defp unsuspend_organization(org_id) do
    {:ok, _} =
      update_organization(
        organization(org_id),
        %{
          is_suspended: false,
          suspended_until: nil
        }
      )
  end

  @doc """
  Resume all organization that are suspended if we are past the suspended time, we check this on an hourly basis for all organizations
  that are in a suspended state via a cron job
  """
  @spec unsuspend_organizations :: any()
  def unsuspend_organizations do
    unsuspend_org_list()
    |> Enum.each(&unsuspend_organization(&1))
  end

  @doc """
  Execute a function across all active organizations. This function is typically called
  by a micron job worker process

  The handler is expected to take the organization id as its first argument. The second argument
  is expected to be a map of arguments passed in by the cron job, and can be ignored if not used

  The list is a restricted list of organizations, so we don't repeatedly do work. The convention is as
  follows:

  list == nil - the action should not be performed for any organization
  list == [] (empty list) - the action should be performed for all organizations
  list == [ values ] - the actions should be performed only for organizations in the values list
  """
  @spec perform_all((... -> nil), map() | nil, list() | [] | nil, Keyword.t()) :: any
  def perform_all(handler, handler_args, list, opts \\ [])

  def perform_all(_handler, _handler_args, nil, _opts), do: nil

  def perform_all(handler, handler_args, list, opts) do
    only_recent = Keyword.get(opts, :only_recent, false)
    # We need to do this for all the active organizations
    list
    |> active_organizations()
    |> recent_organizations(only_recent)
    |> randomize_orgs()
    |> Enum.each(fn {id, name} ->
      perform_handler(handler, handler_args, id, name)
    end)
  rescue
    # If we fail, we need to mark the organization as failed
    # and log the error
    err ->
      "Error occurred while executing cron handler for organizations. Error: #{inspect(err)}, handler: #{inspect(handler)}, handler_args: #{inspect(handler_args)}"
      |> Glific.log_error()
  end

  # lets always perform requests in a random order to
  # avoid starvation of any specific partner
  @spec randomize_orgs(map) :: list
  defp randomize_orgs(orgs) do
    orgs
    |> Enum.reduce(
      [],
      fn {id, %{name: name}}, acc -> [{id, name} | acc] end
    )
    |> then(fn x -> Enum.take_random(x, length(x)) end)
  end

  @active_minutes 720

  @doc """
  Get the organizations which had a message transaction in the last minutes
  as defined by @active_minutes
  """
  @spec recent_organizations(map(), boolean) :: map()
  def recent_organizations(map, false), do: map

  def recent_organizations(map, true) do
    Enum.filter(
      map,
      fn {_id, %{last_communication_at: last_communication_at}} ->
        Timex.diff(DateTime.utc_now(), last_communication_at, :minutes) < @active_minutes
      end
    )
  end

  @spec perform_handler((... -> nil), map() | nil, non_neg_integer(), String.t() | nil) :: any
  defp perform_handler(handler, handler_args, org_id, org_name) do
    Repo.put_process_state(org_id)
    RepoReplica.put_process_state(org_id)
    Logger.info("Starting processes for org id: #{org_id}")

    if is_nil(handler_args) do
      handler.(org_id)
    else
      handler.(org_id, Map.put(handler_args, :organization_name, org_name))
    end
  end

  @doc """
  Get organization's credential by service shortcode
  """
  @spec get_credential(map()) ::
          {:ok, Credential.t()} | {:error, String.t() | [String.t()]}
  def get_credential(%{organization_id: organization_id, shortcode: shortcode}) do
    case Repo.fetch_by(Provider, %{shortcode: shortcode}) do
      {:ok, provider} ->
        Repo.fetch_by(Credential, %{
          organization_id: organization_id,
          provider_id: provider.id
        })

      _ ->
        {:error, ["shortcode", "Invalid provider shortcode."]}
    end
  end

  @doc """
  Creates an organization's credential
  """
  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, any()}
  def create_credential(attrs) do
    case Repo.fetch_by(Provider, %{shortcode: attrs[:shortcode]}) do
      {:ok, provider} ->
        # first delete the cached organization
        organization = get_organization!(attrs.organization_id)
        remove_organization_cache(organization.id, organization.shortcode)
        attrs = Map.merge(attrs, %{provider_id: provider.id})

        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      _ ->
        {:error, ["shortcode", "Invalid provider shortcode: #{attrs[:shortcode]}."]}
    end
  end

  # check for non empty string or nil
  @spec non_nil_string(String.t() | nil) :: boolean()
  defp non_nil_string(str) do
    !is_nil(str) && str != ""
  end

  # Ensures we have all the keys required in the credential to call Gupshup
  @spec valid_bsp?(Credential.t()) :: boolean()
  defp valid_bsp?(credential) do
    bsp = credential.provider.shortcode

    credential.provider.group == "bsp" &&
      validate_secrets?(credential.secrets, bsp)
  end

  @spec validate_secrets?(map(), String.t()) :: boolean()
  defp validate_secrets?(secrets, "gupshup"),
    do:
      non_nil_string(secrets["app_name"]) &&
        non_nil_string(secrets["api_key"])

  defp validate_secrets?(secrets, "gupshup_enterprise"),
    do:
      non_nil_string(secrets["hsm_user_id"]) &&
        non_nil_string(secrets["hsm_password"]) &&
        non_nil_string(secrets["two_way_user_id"]) &&
        non_nil_string(secrets["two_way_password"])

  defp validate_secrets?(_secrets, _bsp),
    do: false

  @doc """
  Updates an organization's credential
  """
  @spec update_credential(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, any}
  def update_credential(%Credential{} = credential, attrs) do
    # delete the cached organization and associated credentials
    organization = organization(credential.organization_id)

    remove_organization_cache(organization.id, organization.shortcode)

    {:ok, credential} =
      credential
      |> Credential.changeset(attrs)
      |> Repo.update()

    credential = credential |> Repo.preload([:provider, :organization])

    credential.organization
    |> credential_update_callback(credential, credential.provider.shortcode)
  end

  @spec credential_update_callback(Organization.t(), Credential.t(), String.t()) ::
          {:ok, any} | {:error, any}
  defp credential_update_callback(organization, credential, "bigquery") do
    Caches.remove(organization.id, [{:provider_token, "bigquery"}])

    case BigQuery.sync_schema_with_bigquery(organization.id) do
      {:ok, _callback} ->
        {:ok, credential}

      {:error, error} ->
        Partners.disable_credential(
          organization.id,
          "bigquery",
          error
        )

        {:error, error}
    end
  end

  defp credential_update_callback(organization, credential, "google_cloud_storage") do
    with true <- credential.is_active,
         {:ok, _} <- GCS.refresh_gcs_setup(organization.id),
         {:ok, _} <- GCS.enable_bucket_logs(organization.id) do
      {:ok, credential}
    else
      false ->
        # credential set to inactive, so no further processing
        {:ok, credential}

      {:error, %{body: %{"error" => %{"message" => message}}}} ->
        {:error, message}

      _ ->
        {:error, "Invalid Credentials"}
    end
  end

  defp credential_update_callback(organization, credential, "dialogflow") do
    case Glific.Dialogflow.get_intent_list(organization.id) do
      {:ok, _callback} -> {:ok, credential}
      {:error, _error} -> {:error, "Invalid Credentials"}
    end
  end

  defp credential_update_callback(organization, credential, "gupshup") do
    result =
      cond do
        not valid_bsp?(credential) ->
          Glific.Metrics.increment("Gupshup Credential Update Failed")
          {:error, "App Name and API Key can't be empty"}

        credential.is_active ->
          update_organization(organization, %{bsp_id: credential.provider.id})

          set_bsp_app_id(organization, "gupshup")

        true ->
          update_organization(organization, %{bsp_id: credential.provider.id})
          {:ok, credential}
      end

    with {:ok, _} <- result do
      GupshupSetupMail.send_gupshup_setup_completion_mail(organization)
    end

    result
  end

  defp credential_update_callback(organization, credential, "gupshup_enterprise") do
    if valid_bsp?(credential) do
      update_organization(organization, %{bsp_id: credential.provider.id})
    end

    {:ok, credential}
  end

  defp credential_update_callback(organization, credential, "maytapi") do
    args = %{"organization_id" => organization.id, "update_credential" => true}

    case Oban.insert(WAWorker.new(args)) do
      {:ok, _job} ->
        Notifications.create_notification(%{
          category: "WhatsApp Groups",
          message: "Syncing of WhatsApp groups and contacts has started in the background.",
          severity: Notifications.types().info,
          organization_id: organization.id,
          entity: %{
            Provider: "Maytapi"
          }
        })

        {:ok, credential}

      {:error, reason} ->
        Logger.error("Failed to enqueue credential update job: #{inspect(reason)}")
        {:error, "Failed to sync WhatsApp data to Glific. Please reach out to Glific Support"}
    end
  end

  defp credential_update_callback(_organization, credential, _provider), do: {:ok, credential}

  @doc """
  Removing organization and service cache
  """
  @spec remove_organization_cache(non_neg_integer, String.t()) :: any()
  def remove_organization_cache(organization_id, shortcode) do
    Caches.remove(@global_organization_id, ["organization_services"])

    Caches.remove(
      @global_organization_id,
      [{:organization, organization_id}, {:organization, shortcode}]
    )

    Caches.remove(
      @global_organization_id,
      ["organization_services"]
    )
  end

  @spec config(map()) :: map() | :error
  defp config(credentials) do
    case Jason.decode(credentials.secrets["service_account"]) do
      {:ok, config} -> config
      _ -> :error
    end
  end

  @doc """
  Common function to get the goth config
  """
  @spec get_goth_token(non_neg_integer, String.t(), Keyword.t()) :: nil | Goth.Token.t()
  def get_goth_token(organization_id, provider_shortcode, opts \\ []) do
    key = {:provider_token, provider_shortcode}
    organization = organization(organization_id)

    if is_nil(organization.services[provider_shortcode]) do
      nil
    else
      Caches.fetch(organization_id, key, fn key -> load_goth_token(key, opts) end)
      |> case do
        {_status, res} when is_map(res) ->
          res

        _ ->
          Logger.error(
            "Could not fetch token for service #{provider_shortcode} for org id: #{organization_id}"
          )

          nil
      end
    end
  end

  @spec load_goth_token(tuple(), Keyword.t()) :: tuple()
  defp load_goth_token(cache_key, goth_opts) do
    {organization_id, {:provider_token, provider_shortcode}} = cache_key

    organization = organization(organization_id)
    credentials = organization.services[provider_shortcode] |> config()

    if credentials == :error do
      {:ignore, nil}
    else
      Goth.Token.fetch(source: {:service_account, credentials, goth_opts})
      |> case do
        {:ok, token} ->
          opts = [ttl: :timer.seconds(token.expires - System.system_time(:second) - 60)]
          Caches.set(organization_id, {:provider_token, provider_shortcode}, token, opts)
          {:ignore, token}

        {:error, error} ->
          Logger.info(
            "Error fetching token for: #{provider_shortcode}, error: #{inspect(error)}, org_id: #{organization_id}"
          )

          handle_token_error(organization_id, provider_shortcode, "#{inspect(error)}")
          {:ignore, nil}
      end
    end
  end

  @spec handle_token_error(non_neg_integer, String.t(), String.t() | any()) :: nil
  defp handle_token_error(organization_id, provider_shortcode, error) when is_binary(error) do
    if String.contains?(error, ["account not found", "invalid_grant"]),
      do:
        disable_credential(
          organization_id,
          provider_shortcode,
          "Invalid credentials, service account not found"
        )

    nil
  end

  defp handle_token_error(_organization_id, _provider_shortcode, error),
    do: raise("Error fetching goth token' #{inspect(error)}")

  @doc """
  Disable a specific credential for the organization
  """
  @spec disable_credential(non_neg_integer, String.t(), String.t()) :: :ok | {:error, list()}
  def disable_credential(organization_id, shortcode, error_message) do
    case Repo.fetch_by(Provider, %{shortcode: shortcode}) do
      {:ok, provider} ->
        # first delete the cached organization
        organization = get_organization!(organization_id)
        remove_organization_cache(organization.id, organization.shortcode)

        Credential
        |> where([c], c.provider_id == ^provider.id)
        |> where([c], c.organization_id == ^organization_id)
        |> Repo.update_all(set: [is_active: false])

        Logger.info("Disable #{shortcode} credential for org_id: #{organization_id}")

        Notifications.create_notification(%{
          category: "Partner",
          message: "Disabling #{shortcode}. #{error_message}",
          severity: Notifications.types().critical,
          organization_id: organization_id,
          entity: %{
            id: provider.id,
            shortcode: shortcode
          }
        })

        :ok

      _ ->
        {:error, ["shortcode", "Invalid provider shortcode to disable: #{shortcode}."]}
    end
  end

  @doc """
  Check if we can allow attachments for this organization. For now, this is a check to
  see if GCS is enabled for this organization
  """
  @spec attachments_enabled?(non_neg_integer) :: boolean()
  def attachments_enabled?(organization_id),
    do:
      organization_id
      |> organization()
      |> Map.get(:services)
      |> Map.has_key?("google_cloud_storage")

  @doc """
  Given an empty list, determine which organizations have been active in the recent
  past
  """
  @spec org_id_list(list(), boolean) :: list()
  def org_id_list([], recent) do
    active_organizations([])
    |> recent_organizations(recent)
    |> Enum.reduce([], fn {id, _map}, acc -> [id | acc] end)
  end

  def org_id_list(list, _recent) do
    Enum.map(
      list,
      fn l ->
        {:ok, int_l} = Glific.parse_maybe_integer(l)
        int_l
      end
    )
  end

  @doc """
  Wrapper query used by various statistics collection routines in Glific
  to return counts on contact with its variations
  """
  @spec contact_organization_query(list()) :: Ecto.Query.t()
  def contact_organization_query(org_id_list) do
    Contact
    # block messages sent to groups
    |> where([c], c.status != :blocked)
    |> where([c], c.organization_id in ^org_id_list)
    |> group_by([c], c.organization_id)
    |> select([c], [count(c.id), c.organization_id])
  end

  @doc """
  Convert global field to map for variable substitution
  """
  @spec get_global_field_map(integer) :: map()
  def get_global_field_map(organization_id), do: organization(organization_id).fields

  @doc """
  Returns a map of organizations services as key value pair
  """
  @spec get_organization_services :: map()
  def get_organization_services do
    case Caches.fetch(
           @global_organization_id,
           "organization_services",
           &load_organization_services/1
         ) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve organization services: #{error}"
        )

      {_, services} ->
        services
    end
  end

  # this is a global cache, so we kinda ignore the cache key
  @spec load_organization_services(tuple()) :: {:commit, map()}
  defp load_organization_services(_cache_key) do
    services =
      active_organizations([])
      |> Enum.reduce(
        %{},
        fn {org_id, _name}, acc ->
          Map.put(acc, org_id, get_org_services_by_id(org_id))
        end
      )
      |> combine_services()

    {:commit, services}
  end

  @doc """
    Get all the services and status for a given organization id.
  """
  @spec get_org_services_by_id(non_neg_integer) :: map()
  def get_org_services_by_id(organization_id) do
    organization = organization(organization_id)

    %{
      "fun_with_flags" =>
        FunWithFlags.enabled?(
          :enable_out_of_office,
          for: %{organization_id: organization_id}
        ),
      "bigquery" => organization.services["bigquery"] != nil,
      "google_cloud_storage" => organization.services["google_cloud_storage"] != nil,
      "dialogflow" => organization.services["dialogflow"] != nil,
      "flow_uuid_display" => Flags.get_flow_uuid_display(organization),
      "roles_and_permission" => Flags.get_roles_and_permission(organization),
      "contact_profile_enabled" => Flags.get_contact_profile_enabled(organization),
      "ticketing_enabled" => Flags.get_ticketing_enabled(organization),
      "whatsapp_group_enabled" => Flags.get_whatsapp_group_enabled(organization),
      "whatsapp_forms_enabled" => Flags.get_whatsapp_forms_enabled?(organization),
      "auto_translation_enabled" =>
        Flags.get_open_ai_auto_translation_enabled(organization) or
          Flags.get_google_auto_translation_enabled(organization),
      "certificate_enabled" => Flags.get_certificate_enabled(organization),
      "interactive_re_response_enabled" =>
        Flags.get_interactive_re_response_enabled(organization),
      "kaapi_enabled" => Flags.get_is_kaapi_enabled(organization),
      "ask_me_bot_enabled" => Flags.get_ask_me_bot_enabled(organization),
      "high_trigger_tps_enabled" =>
        Flags.get_flag_enabled(:high_trigger_tps_enabled, organization),
      "unified_api_enabled" => Flags.get_flag_enabled(:unified_api_enabled, organization)
    }
  end

  @spec add_service(map(), String.t(), boolean(), non_neg_integer) :: map()
  defp add_service(acc, _name, false, _org_id), do: acc

  defp add_service(acc, name, true, org_id) do
    value = Map.get(acc, name, [])
    Map.put(acc, name, [org_id | value])
  end

  @spec combine_services(map()) :: map()
  defp combine_services(services) do
    combined =
      services
      |> Enum.reduce(
        %{},
        fn {org_id, service}, acc ->
          acc
          |> add_service("fun_with_flags", service["fun_with_flags"], org_id)
          |> add_service("bigquery", service["bigquery"], org_id)
          |> add_service("google_cloud_storage", service["google_cloud_storage"], org_id)
          |> add_service("dialogflow", service["dialogflow"], org_id)
        end
      )

    Map.merge(services, combined)
  end

  @doc """
  Set BSP APP id whenever we update the bsp credentials.
  """
  @spec set_bsp_app_id(Organization.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def set_bsp_app_id(org, "gupshup") do
    # restricting this function for BSP only
    {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup", group: "bsp"})

    {:ok, bsp_cred} =
      Repo.fetch_by(Credential, %{provider_id: provider.id, organization_id: org.id})

    case PartnerAPI.fetch_app_details(org.id) do
      %{"id" => app_id} ->
        update_gupshup_secrets(bsp_cred, app_id, org)

      error ->
        Glific.Metrics.increment("Gupshup Credential Update Failed")
        update_gupshup_secrets(bsp_cred, "NA", org)
        {:error, error}
    end
  end

  def set_bsp_app_id(org, shortcode) do
    {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: shortcode, group: "bsp"})

    Repo.fetch_by(Credential, %{provider_id: provider.id, organization_id: org.id})
  end

  @spec update_gupshup_secrets(Credential.t(), String.t(), Organization.t()) ::
          {:ok, Credential.t()} | {:error, any()}
  defp update_gupshup_secrets(bsp_cred, app_id, org) do
    updated_secrets = Map.put(bsp_cred.secrets, "app_id", app_id)
    attrs = %{secrets: updated_secrets, organization_id: org.id}

    bsp_cred
    |> Credential.changeset(attrs)
    |> Repo.update()
    |> tap(fn _ ->
      if app_id != "NA" do
        remove_organization_cache(org.id, org.shortcode)

        Repo.put_process_state(org.id)
        PartnerAPI.apply_gupshup_settings(org.id)
      end
    end)
  end

  @doc """
  Get a List for org data
  """
  @spec list_organization_data(map()) :: [Provider.t(), ...]
  def list_organization_data(args \\ %{}) do
    Repo.list_filter(
      args,
      OrganizationData,
      &Repo.opts_with_name/2,
      &filter_organization_data_with/2
    )
  end

  @spec filter_organization_data_with(Ecto.Queryable.t(), %{optional(atom()) => any}) ::
          Ecto.Queryable.t()
  defp filter_organization_data_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to webhook logs only.
    # We might want to move them in the repo in the future.
    Enum.reduce(filter, query, fn
      {:key, key}, query ->
        from(q in query, where: ilike(q.key, ^"%#{key}%"))

      _, query ->
        query
    end)
  end

  @doc """
  Create a Client Data struct
  """
  @spec create_organization_data(map()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def create_organization_data(attrs \\ %{}) do
    %OrganizationData{}
    |> OrganizationData.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a Client Data struct
  """
  @spec update_organization_data(OrganizationData.t(), map()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def update_organization_data(organization_data, attrs) do
    organization_data
    |> OrganizationData.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete Client Data struct
  """
  @spec delete_organization_data(OrganizationData.t()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def delete_organization_data(%OrganizationData{} = organization_data) do
    Repo.delete(organization_data)
  end

  @doc """
  Insert or update data if key present for OrganizationData table.
  """
  @spec maybe_insert_organization_data(String.t(), map(), non_neg_integer()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def maybe_insert_organization_data(key, data, org_id) do
    # check if the week key is already present in the database
    case Repo.get_by(OrganizationData, %{key: key, organization_id: org_id}) do
      nil ->
        attrs =
          %{}
          |> Map.put(:key, key)
          |> Map.put(:json, data)
          |> Map.put(:organization_id, org_id)

        %OrganizationData{}
        |> OrganizationData.changeset(attrs)
        |> Repo.insert()

      organization_data ->
        organization_data
        |> OrganizationData.changeset(%{json: data})
        |> Repo.update()
    end
  end

  @doc """
  Cron handler for sending dashboard report mail
  """
  @spec send_dashboard_report(non_neg_integer(), map()) :: {:ok, any()} | {:error, String.t()}
  def send_dashboard_report(org_id, %{frequency: frequency}) do
    org = organization(org_id)

    case org.setting.report_frequency do
      ^frequency ->
        Stats.mail_stats(org, frequency)

      nil ->
        Logger.info("Internal Dashboard Report mail frequency is not set")
        {:error, %{message: "mail frequency is not set"}}

      _ ->
        Logger.info("Failed to send Internal Dashboard Report mail")
        {:ok, %{message: "Failed to send Internal Dashboard Report mail"}}
    end
  end
end
