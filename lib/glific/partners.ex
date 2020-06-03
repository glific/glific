defmodule Glific.Partners do
  @moduledoc """
  The Partners context.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo
  alias Glific.Partners.BSP

  @doc """
  Returns the list of bsps.

  ## Examples

      iex> list_bsps()
      [%BSP{}, ...]

  """
  @spec list_bsps(map()) :: [%BSP{}, ...]
  def list_bsps(_args \\ %{}) do
    Repo.all(BSP)
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
    Repo.delete(bsp)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bsp changes.

  ## Examples

      iex> change_bsp(bsp)
      %Ecto.Changeset{data: %BSP{}}

  """
  @spec change_bsp(%BSP{}, map()) :: Ecto.Changeset.t()
  def change_bsp(%BSP{} = bsp, attrs \\ %{}) do
    BSP.changeset(bsp, attrs)
  end
end
