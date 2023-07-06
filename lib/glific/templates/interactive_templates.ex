defmodule Glific.Templates.InteractiveTemplates do
  @moduledoc """
  The InteractiveTemplate Context, which encapsulates and manages interactive templates
  """

  alias Glific.{
    Repo,
    Tags.Tag,
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
      {:term, term}, query ->
        sub_query =
          from(t in Tag,
            where: ilike(t.label, ^"%#{term}%"),
            select: t.id
          )

        from(q in query,
          where:
            ilike(field(q, :label), ^"%#{term}%") or
              fragment("interactive_content::text LIKE ?", ^"%#{term}%") or
              q.tag_id in subquery(sub_query)
        )

      {:type, type}, query ->
        from(q in query, where: q.type == ^type)

      {:tag_ids, tag_ids}, query ->
        from(q in query, where: q.tag_id in ^tag_ids)

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
  Fetches a single interactive template

  Returns `Resource not found` if the Interactive Template does not exist.

  ## Examples

      iex> fetch_interactive_template(123, 1)
        {:ok, %InteractiveTemplate{}}

      iex> fetch_interactive_template(456, 1)
        {:error, ["Elixir.Glific.Templates.InteractiveTemplate", "Resource not found"]}

  """
  @spec fetch_interactive_template(integer) :: {:ok, any} | {:error, any}
  def fetch_interactive_template(id),
    do: Repo.fetch_by(InteractiveTemplate, %{id: id})

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
  Make a copy of a interactive_template
  """
  @spec copy_interactive_template(InteractiveTemplate.t(), map()) ::
          {:ok, InteractiveTemplate.t()} | {:error, String.t()}
  def copy_interactive_template(interactive_template, attrs) do
    attrs =
      %{
        interactive_content: interactive_template.interactive_content,
        send_with_title: interactive_template.send_with_title,
        type: interactive_template.type,
        translations: interactive_template.translations
      }
      |> Map.merge(attrs)

    %InteractiveTemplate{}
    |> InteractiveTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  get interactive body from the interactive content
  """
  @spec get_interactive_body(map()) :: String.t()
  def get_interactive_body(interactive_content),
    do:
      do_get_interactive_body(
        interactive_content,
        interactive_content["type"],
        interactive_content["content"]["type"]
      )

  @spec do_get_interactive_body(map(), String.t(), String.t()) :: String.t()
  defp do_get_interactive_body(interactive_content, "quick_reply", type)
       when type in ["image", "video"],
       do: interactive_content["content"]["text"]

  defp do_get_interactive_body(interactive_content, "quick_reply", "file"),
    do: interactive_content["content"]["url"]

  defp do_get_interactive_body(interactive_content, "quick_reply", "text"),
    do: interactive_content["content"]["text"]

  defp do_get_interactive_body(interactive_content, "list", _) when is_map(interactive_content),
    do: interactive_content["body"]

  defp do_get_interactive_body(_, _, _), do: ""

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

  @doc """
  Cleaning interactive template title as per WhatsApp policy
  """
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
   Get translated interactive template content
  """
  @spec translated_content(InteractiveTemplate.t(), non_neg_integer()) :: map() | nil
  def translated_content(interactive_template, language_id) do
    interactive_template
    |> get_translations(language_id)
    |> get_clean_interactive_content(
      interactive_template.send_with_title,
      interactive_template.type
    )
  end

  @doc """
  Create a message media from interactive content and return id
  """
  @spec get_media(map(), non_neg_integer()) :: non_neg_integer() | nil
  def get_media(interactive_content, organization_id),
    do:
      interactive_content
      |> do_get_media(interactive_content["content"]["type"], organization_id)

  @spec do_get_media(map(), String.t(), non_neg_integer()) :: non_neg_integer() | nil
  defp do_get_media(%{"content" => content}, type, organization_id)
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

  defp do_get_media(_interactive_content, _type, _organization_id), do: nil

  @doc """
  A single function to fetch all the interactive templates related info
  """
  @spec formatted_data(Glific.Templates.InteractiveTemplate.t(), non_neg_integer) ::
          {map, binary, nil | non_neg_integer}
  def formatted_data(interactive_template, language_id) do
    interactive_content = translated_content(interactive_template, language_id)
    body = get_interactive_body(interactive_content)
    media_id = get_media(interactive_content, interactive_template.organization_id)
    {interactive_content, body, media_id}
  end

  @doc """
    Process dynamic interactive messages.
  """
  @spec process_dynamic_interactive_content(map(), list(), map()) :: map()
  def process_dynamic_interactive_content(
        %{"type" => "list"} = interactive_content,
        params,
        attachment
      ) do
    get_in(interactive_content, ["items"])
    |> hd()
    |> Map.put("options", build_list_items(params))
    |> then(&Map.put(interactive_content, "items", [&1]))
    |> process_dynamic_attachments(attachment)
  end

  def process_dynamic_interactive_content(
        %{"type" => "quick_reply"} = interactive_content,
        params,
        attachment
      ) do
    Map.put(interactive_content, "options", build_list_items(params))
    |> process_dynamic_attachments(attachment)
  end

  def process_dynamic_interactive_content(interactive_content, _params, _attachment),
    do: interactive_content

  ## We might need to move this function to gupshup provider
  ## since this is specific to that only but this is fine for now.
  @spec build_list_items(list()) :: list()
  defp build_list_items(params) do
    Enum.map(params, fn
      param when is_map(param) ->
        %{
          "title" => param["label"],
          "description" => "",
          "type" => "text",
          "id" => param["id"] || "",
          "postbackText" => param["id"] || ""
        }

      param ->
        %{
          "title" => param,
          "description" => "",
          "type" => "text"
        }
    end)
  end

  defp process_dynamic_attachments(interactive_content, %{url: url} = attachment_data)
       when url not in [nil, ""] do
    {type, url} = Glific.Messages.get_media_type_from_url(attachment_data[:url])
    content = Map.merge(interactive_content["content"], %{"url" => url, "type" => type})
    Map.put(interactive_content, "content", content)
  end

  defp process_dynamic_attachments(interactive_content, _attachment_data), do: interactive_content
end
