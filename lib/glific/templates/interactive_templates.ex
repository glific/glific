defmodule Glific.Templates.InteractiveTemplates do
  @moduledoc """
  The InteractiveTemplate Context, which encapsulates and manages interactive templates
  """

  alias Glific.{
    Repo,
    Templates.InterativeTemplate
  }

  import Ecto.Query, warn: false

  @doc """
  Returns the list of interactive templates

  ## Examples

      iex> list_interactives()
      [%InterativeTemplate{}, ...]

  """
  @spec list_interactives(map()) :: [InterativeTemplate.t()]
  def list_interactives(args),
    do: Repo.list_filter(args, InterativeTemplate, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of interactive templates, using the same filter as list_interactives
  """
  @spec count_interactives(map()) :: integer
  def count_interactives(args),
    do: Repo.count_filter(args, InterativeTemplate, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to interactive templates only.
    Enum.reduce(filter, query, fn
      {:type, type}, query ->
        from(q in query, where: q.type == ^type)

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single interactive template

  Raises `Ecto.NoResultsError` if the Interactive Template does not exist.

  ## Examples

      iex> get_interactive!(123)
      %InterativeTemplate{}

      iex> get_interactive!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_interactive!(integer) :: InterativeTemplate.t()
  def get_interactive!(id), do: Repo.get!(InterativeTemplate, id)

  @doc """
  Creates an interactive template

  ## Examples

      iex> create_interactive(%{field: value})
      {:ok, %InterativeTemplate{}}

      iex> create_interactive(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_interactive(map()) :: {:ok, InterativeTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_interactive(attrs) do
    %InterativeTemplate{}
    |> InterativeTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an interactive template

  ## Examples

      iex> update_interactive(interactive, %{field: new_value})
      {:ok, %InterativeTemplate{}}

      iex> update_interactive(interactive, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_interactive(InterativeTemplate.t(), map()) ::
          {:ok, InterativeTemplate.t()} | {:error, Ecto.Changeset.t()}
  def update_interactive(%InterativeTemplate{} = interactive, attrs) do
    interactive
    |> InterativeTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an interactive template

  ## Examples

      iex> delete_interactive(interactive)
      {:ok, %InterativeTemplate{}}

      iex> delete_interactive(interactive)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_interactive(InterativeTemplate.t()) ::
          {:ok, InterativeTemplate.t()} | {:error, Ecto.Changeset.t()}
  def delete_interactive(%InterativeTemplate{} = interactive) do
    interactive
    |> InterativeTemplate.changeset(%{})
    |> Repo.delete()
  end
end
