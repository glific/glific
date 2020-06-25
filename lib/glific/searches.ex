defmodule Glific.Searches do
  @moduledoc """
  The Searches context.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo

  alias Glific.Searches.Search

  @doc """
  Returns the list of searches.

  ## Examples

      iex> list_searches()
      [%Search{}, ...]

  """
  @spec list_searches(map()) :: [Search.t()]
  def list_searches(_attrs \\ %{}) do
    Repo.all(Search)
  end

  @doc """
  Gets a single search.

  Raises `Ecto.NoResultsError` if the Search does not exist.

  ## Examples

      iex> get_search!(123)
      %Search{}

      iex> get_search!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_search!(integer) :: Search.t()
  def get_search!(id), do: Repo.get!(Search, id)

  @doc """
  Creates a search.

  ## Examples

      iex> create_search(%{field: value})
      {:ok, %Search{}}

      iex> create_search(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_search(map()) :: {:ok, Search.t()} | {:error, Ecto.Changeset.t()}
  def create_search(attrs) do
    %Search{}
    |> Search.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a search.

  ## Examples

      iex> update_search(search, %{field: new_value})
      {:ok, %Search{}}

      iex> update_search(search, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_search(Search.t(), map()) :: {:ok, Search.t()} | {:error, Ecto.Changeset.t()}
  def update_search(%Search{} = search, attrs) do
    search
    |> Search.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a search.

  ## Examples

      iex> delete_search(search)
      {:ok, %Search{}}

      iex> delete_search(search)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_search(Search.t()) :: {:ok, Search.t()} | {:error, Ecto.Changeset.t()}
  def delete_search(%Search{} = search) do
    Repo.delete(search)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking search changes.

  ## Examples

      iex> change_search(search)
      %Ecto.Changeset{data: %Search{}}

  """
  @spec change_search(Search.t(), map()) :: Ecto.Changeset.t()
  def change_search(%Search{} = search, attrs \\ %{}) do
    Search.changeset(search, attrs)
  end
end
