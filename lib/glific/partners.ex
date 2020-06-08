defmodule Glific.Partners do
  @moduledoc """
  The Partners context. This is the gateway for the application to access/update all the organization
  and BSP information.
  """

  import Ecto.Query, warn: false

  alias Glific.Partners.BSP
  alias Glific.Partners.Organization
  alias Glific.Repo

  @doc """
  Returns the list of bsps.

  ## Examples

      iex> list_bsps()
      [%BSP{}, ...]

  """
  @spec list_bsps(map()) :: [%BSP{}, ...]
  def list_bsps(args \\ %{}) do
    args
    |> Enum.reduce(BSP, fn
      {:order, order}, query ->
        query |> order_by({^order, :name})

      {:filter, filter}, query ->
        query |> filter_bsp_with(filter)
    end)
    |> Repo.all()
  end

  @spec filter_bsp_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_bsp_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        from q in query, where: ilike(q.name, ^"%#{name}%")

      {:url, url}, query ->
        from q in query, where: ilike(q.url, ^"%#{url}%")
    end)
  end

  @doc """
  Gets a single bsp.

  Raises `Ecto.NoResultsError` if the Bsp does not exist.

  ## Examples

      iex> get_bsp!(123)
      %BSP{}

      iex> get_bsp!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_bsp!(id :: integer) :: %BSP{}
  def get_bsp!(id), do: Repo.get!(BSP, id)

  @doc """
  Creates a bsp.

  ## Examples

      iex> create_bsp(%{field: value})
      {:ok, %BSP{}}

      iex> create_bsp(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_bsp(map()) :: {:ok, %BSP{}} | {:error, Ecto.Changeset.t()}
  def create_bsp(attrs \\ %{}) do
    %BSP{}
    |> BSP.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a bsp.

  ## Examples

      iex> update_bsp(bsp, %{field: new_value})
      {:ok, %BSP{}}

      iex> update_bsp(bsp, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_bsp(%BSP{}, map()) :: {:ok, %BSP{}} | {:error, Ecto.Changeset.t()}
  def update_bsp(%BSP{} = bsp, attrs) do
    bsp
    |> BSP.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bsp.

  ## Examples

      iex> delete_bsp(bsp)
      {:ok, %BSP{}}

      iex> delete_bsp(bsp)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_bsp(%BSP{}) :: {:ok, %BSP{}} | {:error, Ecto.Changeset.t()}
  def delete_bsp(%BSP{} = bsp) do
    bsp
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:organizations)
    |> Repo.delete()
  end

  @doc ~S"""
  Returns an `%Ecto.Changeset{}` for tracking bsp changes.

  ## Examples

      iex> change_bsp(bsp)
      %Ecto.Changeset{data: %BSP{}}

  """
  @spec change_bsp(%BSP{}, map()) :: Ecto.Changeset.t()
  def change_bsp(%BSP{} = bsp, attrs \\ %{}) do
    BSP.changeset(bsp, attrs)
  end

  @doc ~S"""
  Returns the list of organizations.

  ## Examples

      iex> Glific.Partners.list_organizations()
      [%Glific.Partners.Organization{}, ...]

  """
  @spec list_organizations(map()) :: [Organization.t()]
  def list_organizations(args \\ %{}) do
    args
    |> Enum.reduce(Organization, fn
      {:order, order}, query ->
        query |> order_by({^order, :name})

      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.all()
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        from q in query, where: ilike(q.name, ^"%#{name}%")

      {:display_name, display_name}, query ->
        from q in query, where: ilike(q.display_name, ^"%#{display_name}%")

      {:contact_name, contact_name}, query ->
        from q in query, where: ilike(q.contact_name, ^"%#{contact_name}%")

      {:email, email}, query ->
        from q in query, where: ilike(q.email, ^"%#{email}%")

      {:bsp, bsp}, query ->
        from q in query,
          join: c in assoc(q, :bsp),
          where: ilike(c.name, ^"%#{bsp}%")

      {:wa_number, wa_number}, query ->
        from q in query, where: ilike(q.wa_number, ^"%#{wa_number}%")
    end)
  end

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
  def update_organization(%Organization{} = bsp, attrs) do
    bsp
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
end
