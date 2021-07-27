defmodule Glific.Templates.InteractiveTemplates do
  @moduledoc """
  The InteractiveTemplate Context, which encapsulates and manages interactive templates
  """

  alias Glific.{
    Repo,
    Templates.InteractiveTemplate
  }

  import Ecto.Query, warn: false

  @doc """
  Returns the list of interactive templates

  ## Examples

      iex> list_interactives()
      [%InteractiveTemplate{}, ...]

  """
  @spec list_interactives(map()) :: [InteractiveTemplate.t()]
  def list_interactives(args),
    do: Repo.list_filter(args, InteractiveTemplate, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of interactive templates, using the same filter as list_interactives
  """
  @spec count_interactive_templates(map()) :: integer
  def count_interactive_templates(args),
    do: Repo.count_filter(args, InteractiveTemplate, &filter_with/2)

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

      iex> get_interactive_template!(123)
      %InteractiveTemplate{}

      iex> get_interactive_template!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_interactive_template!(integer) :: InteractiveTemplate.t()
  def get_interactive_template!(id), do: Repo.get!(InteractiveTemplate, id)

  @doc """
  Creates an interactive template

  ## Examples

      iex> create_interactive_template(%{field: value})
      {:ok, %InteractiveTemplate{}}

      iex> create_interactive_template(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_interactive_template(map()) ::
          {:ok, InteractiveTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_interactive_template(attrs) do
    %InteractiveTemplate{}
    |> InteractiveTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an interactive template

  ## Examples

      iex> update_interactive_template(interactive, %{field: new_value})
      {:ok, %InteractiveTemplate{}}

      iex> update_interactive_template(interactive, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_interactive_template(InteractiveTemplate.t(), map()) ::
          {:ok, InteractiveTemplate.t()} | {:error, Ecto.Changeset.t()}
  def update_interactive_template(%InteractiveTemplate{} = interactive, attrs) do
    interactive
    |> InteractiveTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an interactive template

  ## Examples

      iex> delete_interactive_template(interactive)
      {:ok, %InteractiveTemplate{}}

      iex> delete_interactive_template(interactive)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_interactive_template(InteractiveTemplate.t()) ::
          {:ok, InteractiveTemplate.t()} | {:error, Ecto.Changeset.t()}
  def delete_interactive_template(%InteractiveTemplate{} = interactive) do
    interactive
    |> InteractiveTemplate.changeset(%{})
    |> Repo.delete()
  end

  @doc """
  get interactive body from the interactive content
  """
  @spec get_interactive_body(map(), String.t(), String.t()) :: String.t()
  def get_interactive_body(interactive_content, "quick_reply", type)
      when type in ["image", "video"],
      do: interactive_content["content"]["caption"]

  def get_interactive_body(interactive_content, "quick_reply", "file"),
    do: interactive_content["content"]["url"]

  def get_interactive_body(interactive_content, "quick_reply", "text"),
    do: interactive_content["content"]["text"]

  def get_interactive_body(interactive_content, "list", _),
    do: interactive_content["body"]

  def get_interactive_body(_, _, _), do: ""

  @doc """
  Check for translation of interactive message
  """
  @spec check_translations(InteractiveTemplate.t(), non_neg_integer()) :: map()
  def check_translations(interactive_template, language_id) do
    Map.get(
      interactive_template.translations,
      Integer.to_string(language_id),
      interactive_template.interactive_content
    )
  end
end
