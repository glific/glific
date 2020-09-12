defmodule Glific.Partners do
  @moduledoc """
  The Partners context. This is the gateway for the application to access/update all the organization
  and Provider information.
  """

  use Publicist

  import Ecto.Query, warn: false

  alias Glific.{
    Caches,
    Partners.Organization,
    Partners.Provider,
    Repo
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
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:url, url}, query ->
        from q in query, where: ilike(q.url, ^"%#{url}%")

      _, query ->
        query
    end)
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

  @spec get_provider_key(non_neg_integer) :: String.t()
  defp get_provider_key(organization_id) do
    case Application.fetch_env(
           :glific,
           String.to_atom("provider_key_#{organization_id}")
         ) do
      {:ok, value} -> value
      :error -> raise ArgumentError
    end
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
          |> set_out_of_office_values()
          |> Map.put(:provider_key, get_provider_key(organization_id))

        Caches.set(organization_id, "organization", organization)
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

  @doc """
  Execute a function across all active organizations. This function is typically called
  by a cron job worker process

  The handler is expected to take the organization id as its first argument. The second argument
  is expected to be a map of arguments passed in by the cron job, and can be ignored if not used
  """
  @spec perform_all((non_neg_integer, map() -> nil), map()) :: :ok
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
end
