defmodule Glific.Partners do
  @moduledoc """
  The Partners context. This is the gateway for the application to access/update all the organization
  and Provider information.
  """

  use Publicist

  import Ecto.Query, warn: false

  alias Glific.{
    Caches,
    Flags,
    Partners.Credential,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Settings.Language
  }

  @doc """
  Returns the list of providers.

  ## Examples

      iex> list_providers()
      [%Provider{}, ...]

  """
  @spec list_providers(map()) :: [%Provider{}, ...]
  def list_providers(args \\ %{}),
    do: Repo.list_filter(args, Provider, &Repo.opts_with_name/2, &filter_provider_with/2)

  @doc """
  Return the count of providers, using the same filter as list_providers
  """
  @spec count_providers(map()) :: integer
  def count_providers(args \\ %{}),
    do: Repo.count_filter(args, Provider, &filter_provider_with/2)

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
  @spec get_provider!(id :: integer) :: %Provider{}
  def get_provider!(id), do: Repo.get!(Provider, id)

  @doc """
  Creates a provider.

  ## Examples

      iex> create_provider(%{field: value})
      {:ok, %Provider{}}

      iex> create_provider(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_provider(map()) :: {:ok, %Provider{}} | {:error, Ecto.Changeset.t()}
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
  @spec update_provider(%Provider{}, map()) :: {:ok, %Provider{}} | {:error, Ecto.Changeset.t()}
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
  @spec delete_provider(%Provider{}) :: {:ok, %Provider{}} | {:error, Ecto.Changeset.t()}
  def delete_provider(%Provider{} = provider) do
    provider
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:organizations)
    |> Repo.delete()
  end

  @doc ~S"""
  Returns an `%Ecto.Changeset{}` for tracking provider changes.

  ## Examples

      iex> change_provider(provider)
      %Ecto.Changeset{data: %Provider{}}

  """
  @spec change_provider(%Provider{}, map()) :: Ecto.Changeset.t()
  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  @doc ~S"""
  Returns the list of organizations.

  ## Examples

      iex> Glific.Partners.list_organizations()
      [%Glific.Partners.Organization{}, ...]

  """
  @spec list_organizations(map()) :: [Organization.t()]
  def list_organizations(args \\ %{}),
    do: Repo.list_filter(args, Organization, &Repo.opts_with_name/2, &filter_organization_with/2)

  @doc """
  List of organizations that are active within the system
  """
  @spec active_organizations :: map()
  def active_organizations do
    Organization
    |> where([q], q.is_active == true)
    |> select([q], [q.id, q.name])
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      [id, value] = row
      Map.put(acc, id, value)
    end)
  end

  @doc """
  Return the count of organizations, using the same filter as list_organizations
  """
  @spec count_organizations(map()) :: integer
  def count_organizations(args \\ %{}),
    do: Repo.count_filter(args, Organization, &filter_organization_with/2)

  # codebeat:disable[ABC]
  @spec filter_organization_with(Ecto.Queryable.t(), %{optional(atom()) => any}) ::
          Ecto.Queryable.t()
  defp filter_organization_with(query, filter) do
    filter = Map.delete(filter, :organization_id)
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:email, email}, query ->
        from q in query, where: ilike(q.email, ^"%#{email}%")

      {:provider, provider}, query ->
        from q in query,
          join: c in assoc(q, :provider),
          where: ilike(c.name, ^"%#{provider}%")

      {:provider_phone, provider_phone}, query ->
        from q in query, where: ilike(q.provider_phone, ^"%#{provider_phone}%")

      {:default_language, default_language}, query ->
        from q in query,
          join: c in assoc(q, :default_language),
          where: ilike(c.label, ^"%#{default_language}%")

      _, query ->
        query
    end)
  end

  # codebeat:enable[ABC]

  @doc ~S"""
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the organization does not exist.

  ## Examples

      iex> Glific.Partners.get_organization!(1)
      %Glific.Partners.Organization{}

      iex> Glific.Partners.get_organization!(-1)
      ** (Ecto.NoResultsError)

  """
  @spec get_organization!(integer) :: Organization.t()
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc ~S"""
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
    |> Repo.insert()
  end

  @doc ~S"""
  Updates an organization.

  ## Examples

      iex> Glific.Partners.update_organization(Organization, %{name: new_name})
      {:ok, %Glific.Partners.Organization{}}

      iex> Glific.Partners.update_organization(Organization, %{abc: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_organization(Organization.t(), map()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def update_organization(%Organization{} = organization, attrs) do
    # first delete the cached organization
    Caches.remove(organization.id, ["organization"])

    # fetch opted in contacts
    fetch_opted_in_contacts(organization)

    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc ~S"""
  Deletes an Orgsanization.

  ## Examples

      iex> Glific.Partners.delete_organization(organization)
      {:ok, %Glific.Partners.Organization{}}

      iex> delete_organization(organization)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_organization(Organization.t()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def delete_organization(%Organization{} = organization) do
    Repo.delete(organization)
  end

  @doc ~S"""
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
  Cache the entire organization structure.

  In v0.4, we should cache it based on organization id, and that should be a parameter
  """
  @spec organization(non_neg_integer) :: Organization.t()
  def organization(organization_id) do
    case Caches.get(organization_id, "organization") do
      {:ok, value} when value in [nil, false] ->
        organization =
          get_organization!(organization_id)
          |> Repo.preload(:provider)
          |> set_provider_info()
          |> set_out_of_office_values()
          |> set_languages()
          |> set_credentials()

        Caches.set(organization_id, "organization", organization)

        # also update the flags table with updated values
        Flags.init(organization.id)

        organization

      {:ok, organization} ->
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

  # Lets cache all provider specific info in the organization entity since
  # we use it on all sending / receiving of messages
  @spec set_provider_info(map()) :: map()
  defp set_provider_info(organization) do
    {:ok, credential} =
      Repo.fetch_by(
        Credential,
        %{organization_id: organization.id, provider_id: organization.provider_id}
      )

    organization
    |> Map.put(:provider_key, credential.secrets["api_key"])
    |> Map.put(
      :provider_worker,
      ("Elixir." <> credential.keys["worker"]) |> String.to_existing_atom()
    )
    |> Map.put(
      :provider_handler,
      ("Elixir." <> credential.keys["handler"]) |> String.to_existing_atom()
    )
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

    credentials_map =
      Enum.reduce(credentials, %{}, fn credential, acc ->
        Map.merge(acc, %{
          credential.provider.shortcode => %{keys: credential.keys, secrets: credential.secrets}
        })
      end)

    organization
    |> Map.put(:credentials, credentials_map)
  end

  @doc """
  Execute a function across all active organizations. This function is typically called
  by a cron job worker process

  The handler is expected to take the organization id as its first argument. The second argument
  is expected to be a map of arguments passed in by the cron job, and can be ignored if not used
  """
  @spec perform_all((... -> nil), map() | nil) :: :ok
  def perform_all(handler, handler_args) do
    # We need to do this for all the active organizations
    active_organizations()
    |> Enum.each(fn {id, name} ->
      if is_nil(handler_args),
        do: handler.(id),
        else:
          handler.(
            id,
            Map.put(handler_args, :organization_name, name)
          )
    end)

    :ok
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(Organization.t()) :: :ok | any
  def fetch_opted_in_contacts(organization) do
    {:ok, credential} =
      Repo.fetch_by(
        Credential,
        %{organization_id: organization.id, provider_id: organization.provider_id}
      )

    organization = organization |> Repo.preload(:provider)
    url = credential.keys["api_end_point"] <> "/users/" <> organization.provider_appname

    api_key = credential.secrets["api_key"]

    with {:ok, response} <- Tesla.get(url, headers: [{"apikey", api_key}]),
         {:ok, response_data} <- Jason.decode(response.body),
         false <- is_nil(response_data["users"]) do
      users = response_data["users"]

      Enum.each(users, fn user ->
        {:ok, last_message_at} = DateTime.from_unix(user["lastMessageTimeStamp"], :millisecond)
        {:ok, optin_time} = DateTime.from_unix(user["optinTimeStamp"], :millisecond)

        phone = user["countryCode"] <> user["phoneCode"]

        Glific.Contacts.upsert(%{
          phone: phone,
          last_message_at: last_message_at |> DateTime.truncate(:second),
          optin_time: optin_time |> DateTime.truncate(:second),
          provider_status: check_provider_status(last_message_at),
          organization_id: organization.id,
          language_id: organization.default_language_id
        })
      end)
    end
  end

  @spec check_provider_status(DateTime.t()) :: atom()
  defp check_provider_status(last_message_at) do
    if Timex.diff(DateTime.utc_now(), last_message_at, :hours) < 24 do
      :session_and_hsm
    else
      :hsm
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
        Caches.remove(attrs.organization_id, ["organization"])

        attrs = Map.merge(attrs, %{provider_id: provider.id})

        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      _ ->
        {:error, ["shortcode", "Invalid provider shortcode."]}
    end
  end

  @doc """
  Updates an organization's credential
  """
  @spec update_credential(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def update_credential(%Credential{} = credential, attrs) do
    # first delete the cached organization
    Caches.remove(credential.organization_id, ["organization"])

    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
    we will check if the goth config are loaded for the email
    if not we will load them again.
  """
  @spec check_and_load_goth_config(String.t(), non_neg_integer) :: :ok
  def check_and_load_goth_config(email, org_id) do
    Goth.Config.get(email, "private_key_id")
    |> load_goth_config(org_id)
  end

  @spec load_goth_config(any(), non_neg_integer) :: :ok
  defp load_goth_config(:error, org_id) do
    {:ok, credential} =
      get_credential(%{
        organization_id: org_id,
        shortcode: "goth"
      })

    credential.secrets["json"]
    |> Goth.Config.add_config()

    :ok
  end

  defp load_goth_config(_, _), do: :ok
end
