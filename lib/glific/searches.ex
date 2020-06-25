defmodule Glific.Searches do
  @moduledoc """
  The Searches context.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo

  alias Glific.Searches.SavedSearch

  @doc """
  Returns the list of searches.

  ## Examples

      iex> list_saved_searches()
      [%SavedSearch{}, ...]

  """
  @spec list_saved_searches(map()) :: [SavedSearch.t()]
  def list_saved_searches(_attrs \\ %{}) do
    Repo.all(SavedSearch)
  end

  @doc """
  Gets a single search.

  Raises `Ecto.NoResultsError` if the SavedSearch does not exist.

  ## Examples

      iex> get_saved_search!(123)
      %SavedSearch{}

      iex> get_saved_search!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_saved_search!(integer) :: SavedSearch.t()
  def get_saved_search!(id), do: Repo.get!(SavedSearch, id)

  @doc """
  Creates a search.

  ## Examples

      iex> create_saved_search(%{field: value})
      {:ok, %SavedSearch{}}

      iex> create_saved_search(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_saved_search(map()) :: {:ok, SavedSearch.t()} | {:error, Ecto.Changeset.t()}
  def create_saved_search(attrs) do
    %SavedSearch{}
    |> SavedSearch.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a search.

  ## Examples

      iex> update_saved_search(search, %{field: new_value})
      {:ok, %SavedSearch{}}

      iex> update_saved_search(search, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_saved_search(SavedSearch.t(), map()) :: {:ok, SavedSearch.t()} | {:error, Ecto.Changeset.t()}
  def update_saved_search(%SavedSearch{} = search, attrs) do
    search
    |> SavedSearch.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a search.

  ## Examples

      iex> delete_saved_search(search)
      {:ok, %SavedSearch{}}

      iex> delete_saved_search(search)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_saved_search(SavedSearch.t()) :: {:ok, SavedSearch.t()} | {:error, Ecto.Changeset.t()}
  def delete_saved_search(%SavedSearch{} = search) do
    Repo.delete(search)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking search changes.

  ## Examples

      iex> change_saved_search(search)
      %Ecto.Changeset{data: %Search{}}

  """
  @spec change_saved_search(SavedSearch.t(), map()) :: Ecto.Changeset.t()
  def change_saved_search(%SavedSearch{} = search, attrs \\ %{}) do
    SavedSearch.changeset(search, attrs)
  end
end
