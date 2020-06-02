defmodule Glific.Partners do
  @moduledoc """
  The Partners context.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo

  alias Glific.Partners.BSP

  @spec list_bsps() :: String.t()
  @doc """
  Returns the list of bsps.

  ## Examples

      iex> list_bsps()
      [%BSP{}, ...]

  """
  def list_bsps do
    Repo.all(BSP)
  end

  @spec get_bsp!(any) :: any
  @doc """
  Gets a single bsp.

  Raises `Ecto.NoResultsError` if the Bsp does not exist.

  ## Examples

      iex> get_bsp!(123)
      %BSP{}

      iex> get_bsp!(456)
      ** (Ecto.NoResultsError)

  """
  def get_bsp!(id), do: Repo.get!(BSP, id)

  @spec create_bsp(any) :: any
  @doc """
  Creates a bsp.

  ## Examples

      iex> create_bsp(%{field: value})
      {:ok, %BSP{}}

      iex> create_bsp(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_bsp(attrs \\ %{}) do
    %BSP{}
    |> BSP.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_bsp(%BSP{}, any) :: any
  @doc """
  Updates a bsp.

  ## Examples

      iex> update_bsp(bsp, %{field: new_value})
      {:ok, %BSP{}}

      iex> update_bsp(bsp, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_bsp(%BSP{} = bsp, attrs) do
    bsp
    |> BSP.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_bsp(%BSP{}) :: any
  @doc """
  Deletes a bsp.

  ## Examples

      iex> delete_bsp(bsp)
      {:ok, %BSP{}}

      iex> delete_bsp(bsp)
      {:error, %Ecto.Changeset{}}

  """
  def delete_bsp(%BSP{} = bsp) do
    Repo.delete(bsp)
  end

  @spec change_bsp(%BSP{}, any) :: any
  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bsp changes.

  ## Examples

      iex> change_bsp(bsp)
      %Ecto.Changeset{data: %BSP{}}

  """
  def change_bsp(%BSP{} = bsp, attrs \\ %{}) do
    BSP.changeset(bsp, attrs)
  end
end
