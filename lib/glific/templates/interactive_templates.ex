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
      do: interactive_content["content"]["text"]

  def get_interactive_body(interactive_content, "quick_reply", "file"),
    do: interactive_content["content"]["url"]

  def get_interactive_body(interactive_content, "quick_reply", "text"),
    do: interactive_content["content"]["text"]

  def get_interactive_body(interactive_content, "list", _),
    do: interactive_content["body"]

  def get_interactive_body(_, _, _), do: ""

  @doc """
  Fetch for translation of interactive message
  """
  @spec get_translations(InteractiveTemplate.t(), non_neg_integer()) :: map()
  def get_translations(interactive_template, language_id) do
    Map.get(
      interactive_template.translations,
      Integer.to_string(language_id),
      interactive_template.interactive_content
    )
  end

  @doc """
  Returns interactive content based on send_interactive_title field
  """
  @spec get_clean_interactive_content(map(), boolean(), atom()) :: map()
  def get_clean_interactive_content(interactive_content, false, :list),
    do: interactive_content |> Map.delete("title")

  def get_clean_interactive_content(
        %{"content" => %{"type" => type}} = interactive_content,
        false,
        :quick_reply
      )
      when type in ["text"] do
    updated_content = interactive_content["content"] |> Map.delete("header")
    Map.put(interactive_content, "content", updated_content)
  end

  def get_clean_interactive_content(interactive_content, _send_interactive_title, _type),
    do: interactive_content

  @spec clean_string(String.t()) :: String.t()
  defp clean_string(str), do: String.replace(str, ~r/[\p{P}\p{S}\p{C}]+/u, "")

  #  Cleaning interactive template title as per WhatsApp policy
  @spec clean_template_title(map() | nil) :: map() | nil
  def clean_template_title(nil), do: nil

  def clean_template_title(%{"type" => type, "title" => title} = interactive_content)
      when type == "list",
      do: put_in(interactive_content["title"], clean_string(title))

  def clean_template_title(%{"type" => type, "content" => content} = interactive_content)
      when type == "quick_reply" do
    if is_nil(content["header"]),
      do: interactive_content,
      else: put_in(interactive_content["content"]["header"], clean_string(content["header"]))
  end

  def clean_template_title(interactive_content), do: interactive_content

  @doc """
  Create a message media from interactive content and return id
  """
  @spec get_media(map(), String.t(), non_neg_integer()) :: non_neg_integer() | nil
  def get_media(%{"content" => content}, type, organization_id)
      when type in ["image", "file", "video"] do
    {:ok, media} =
      %{
        caption: content["caption"],
        organization_id: organization_id,
        source_url: content["url"],
        url: content["url"]
      }
      |> Glific.Messages.create_message_media()

    media.id
  end

  def get_media(_interactive_content, _type, _organization_id), do: nil
end
