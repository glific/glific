defmodule Glific.Profiles do
  @moduledoc """
  The Profiles context.
  """

  import Ecto.Query, warn: false

  alias Glific.{Profiles.Profile, Repo}

  @doc """
  Returns the list of profiles.

  ## Examples

      iex> list_profiles()
      [%Profile{}, ...]

  Get the list of profiles filtered by various search options
  Include profiles only if within list of groups
  Include profiles only if have list of tags
  """
  @spec list_profiles(map()) :: [Contact.t()]
  def list_profiles(args) do
    IO.inspect(args)

    args
    |> Repo.list_filter_query(Profile, nil, &filter_with/2)
    |> Repo.all()
  end

  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    IO.inspect(query)

    Enum.reduce(filter, query, fn
      {:contact_id, contact_id}, query ->
        from(q in query, where: q.contact_id == ^contact_id)

      {:organization_id, organization_id}, query ->
        from(q in query, where: q.organization_id == ^organization_id)

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single profile.

  Raises `Ecto.NoResultsError` if the Profile does not exist.

  ## Examples

      iex> get_profile!(123)
      %Profile{}

      iex> get_profile!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_profile!(integer) :: Profile.t()
  def get_profile!(id), do: Repo.get!(Profile, id)

  @doc """
  Creates a profile.

  ## Examples

      iex> create_profile(%{field: value})
      {:ok, %Profile{}}

      iex> create_profile(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_profile(map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def create_profile(attrs \\ %{}) do
    %Profile{}
    |> Profile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a profile.

  ## Examples

      iex> update_profile(profile, %{field: new_value})
      {:ok, %Profile{}}

      iex> update_profile(profile, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_profile(Profile.t(), map()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a profile.

  ## Examples

      iex> delete_profile(profile)
      {:ok, %Profile{}}

      iex> delete_profile(profile)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_profile(Profile.t()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def delete_profile(%Profile{} = profile) do
    Repo.delete(profile)
  end
end
