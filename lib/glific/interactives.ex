defmodule Glific.Interactives do
  @moduledoc """
  The Interactives Context, which encapsulates and manages interactives
  """

  alias Glific.{
    Messages.Interactive,
    Repo
  }

  import Ecto.Query, warn: false

  @doc """
  Returns the list of interactives.

  ## Examples

      iex> list_interactives()
      [%Interactive{}, ...]

  """
  @spec list_interactives(map()) :: [Interactive.t()]
  def list_interactives(args),
    do: Repo.list_filter(args, Interactive, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of interactives, using the same filter as list_interactives
  """
  @spec count_interactives(map()) :: integer
  def count_interactives(args),
    do: Repo.count_filter(args, Interactive, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to consulting hours only.
    Enum.reduce(filter, query, fn
      {:type, type}, query ->
        from q in query, where: q.type == ^type

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single interactive.

  Raises `Ecto.NoResultsError` if the Interactive does not exist.

  ## Examples

      iex> get_interactive!(123)
      %Interactive{}

      iex> get_interactive!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_interactive!(integer) :: Interactive.t()
  def get_interactive!(id), do: Repo.get!(Interactive, id)

  @doc """
  Creates a interactive.

  ## Examples

      iex> create_interactive(%{field: value})
      {:ok, %Interactive{}}

      iex> create_interactive(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_interactive(map()) :: {:ok, Interactive.t()} | {:error, Ecto.Changeset.t()}
  def create_interactive(attrs) do
    %Interactive{}
    |> Interactive.changeset(attrs)
    |> IO.inspect()
    |> Repo.insert()
  end

  @doc """
  Updates a interactive.

  ## Examples

      iex> update_interactive(interactive, %{field: new_value})
      {:ok, %Interactive{}}

      iex> update_interactive(interactive, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_interactive(Interactive.t(), map()) ::
          {:ok, Interactive.t()} | {:error, Ecto.Changeset.t()}
  def update_interactive(%Interactive{} = interactive, attrs) do
    interactive
    |> Interactive.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a interactive.

  ## Examples

      iex> delete_interactive(interactive)
      {:ok, %Interactive{}}

      iex> delete_interactive(interactive)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_interactive(Interactive.t()) ::
          {:ok, Interactive.t()} | {:error, Ecto.Changeset.t()}
  def delete_interactive(%Interactive{} = interactive) do
    interactive
    |> Interactive.changeset(%{})
    |> Repo.delete()
  end
end
