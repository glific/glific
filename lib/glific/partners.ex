defmodule Glific.Partners do
  @moduledoc """
  The Partners context. This is the gateway for the application to access/update all the organization
  and Provider information.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Caches,
    Contacts.Contact,
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
      {:display_name, display_name}, query ->
        from q in query, where: ilike(q.display_name, ^"%#{display_name}%")

      {:contact_name, contact_name}, query ->
        from q in query, where: ilike(q.contact_name, ^"%#{contact_name}%")

      {:email, email}, query ->
        from q in query, where: ilike(q.email, ^"%#{email}%")

      {:provider, provider}, query ->
        from q in query,
          join: c in assoc(q, :provider),
          where: ilike(c.name, ^"%#{provider}%")

      {:provider_number, provider_number}, query ->
        from q in query, where: ilike(q.provider_number, ^"%#{provider_number}%")

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
  def update_organization(%Organization{} = provider, attrs) do
    provider
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc ~S"""
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
  Temorary hack to get the organization id while we get tests to pass
  """
  @spec organization_id() :: integer()
  def organization_id do
    case Caches.get("organization_id") do
      {:ok, false} ->
        organization = Organization |> Ecto.Query.first() |> Repo.one()
        Caches.set("organization_id", organization.id)
        organization.id

      {:ok, organization_id} ->
        organization_id
    end
  end

  @doc """
  This contact id is special since it is the sender for all outbound messages
  and the receiver for all inbound messages
  """
  @spec organization_contact_id() :: integer()
  def organization_contact_id do
    # Get contact id
    case Caches.get("organization_contact_id") do
      {:ok, false} ->
        contact_id =
          Contact
          |> join(:inner, [c], o in Organization, on: c.id == o.contact_id)
        |> select([c, _o], c.id)
        |> limit(1)
        |> Repo.one()

        Caches.set("organization_contact_id", contact_id)
        contact_id

      {:ok, contact_id} ->
        contact_id
    end
  end
end
