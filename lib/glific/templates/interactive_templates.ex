defmodule Glific.Templates.InteractiveTemplates do
  @moduledoc """
  The InteractiveTemplate Context, which encapsulates and manages interactive templates
  """

  # require Logger

  alias Glific.{
    Flows.Translate.GoogleTranslate,
    Repo,
    Settings,
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

  @spec meet_waba_title_spec(String.t()) :: String.t()
  defp meet_waba_title_spec(str), do: str |> String.slice(0..1024)

  @spec meet_waba_button_spec(String.t()) :: String.t()
  defp meet_waba_button_spec(str), do: str |> String.slice(0..20)

  @spec do_get_interactive_body(map(), String.t(), String.t()) :: String.t()
  defp do_get_interactive_body(interactive_content, "quick_reply", type)
       when type in ["image", "video"],
       do: interactive_content["content"]["text"] |> meet_waba_title_spec()

  defp do_get_interactive_body(interactive_content, "quick_reply", "file"),
    do: interactive_content["content"]["url"]

  defp do_get_interactive_body(interactive_content, "quick_reply", "text"),
    do: interactive_content["content"]["text"] |> meet_waba_title_spec()

  defp do_get_interactive_body(interactive_content, "list", _) when is_map(interactive_content),
    do: interactive_content["body"] |> meet_waba_title_spec()

  defp do_get_interactive_body(interactive_content, "location_request_message", _)
       when is_map(interactive_content),
       do: interactive_content["body"]["text"]

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
  defp clean_string(str, length \\ 60),
    do:
      str
      |> String.replace(~r/[\p{P}\p{S}\p{C}]+/u, "")
      |> String.slice(0..length)

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
    IO.inspect(interactive_template)

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
        url: content["url"],
        flow: :outbound
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
    IO.inspect(interactive_template)
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
    interactive_content
    |> get_in(["items"])
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
          "title" => param["label"] |> meet_waba_button_spec(),
          "description" => "",
          "type" => "text",
          "id" => param["id"] || "",
          "postbackText" => param["id"] || ""
        }

      param ->
        %{
          "title" => param |> meet_waba_button_spec(),
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

  @spec translate_interactive_template(InteractiveTemplate.t()) ::
          {:ok, InteractiveTemplate.t()} | {:error, String.t()}
  def translate_interactive_template(%InteractiveTemplate{} = interactive_template) do
    organization_id = interactive_template.organization_id
    language_code_map = Settings.locale_id_map()

    active_languages =
      Settings.get_language_code(organization_id)

    contents_to_translate =
      [
        content["content"]["header"],
        content["content"]["text"]
      ] ++ Enum.map(content["options"], fn option -> option["title"] end)

    translated_contents =
      Enum.reduce(active_languages, %{}, fn {lang_name, lang_code}, acc ->
        translations =
          GoogleTranslate.translate(contents_to_translate, "English", lang_name,
            org_id: organization_id
          )

      case translations do
        {:ok, translated_content} ->
          [translated_label | remaining_translations] = translated_content

          if Map.has_key?(content["content"], "caption") do
            [caption, text | options] = remaining_translations

            options_translated = do_options_translated(content, options)

            translated_content_map =
              %{
                "header" => translated_label,
                "caption" => caption,
                "text" => text,
                "type" => content["content"]["type"]
              }
              |> add_url_if_present(content)

            translated_template = %{
              "content" => translated_content_map,
              "options" => options_translated,
              "type" => "quick_reply"
            }

            Map.put(
              acc,
              Integer.to_string(Map.get(language_code_map, lang_code)),
              translated_template
            )
          else
            [text | options] = remaining_translations

            options_translated = do_options_translated(content, options)

            translated_content_map =
              %{
                "header" => translated_label,
                "text" => text,
                "type" => content["content"]["type"]
              }
              |> add_url_if_present(content)

            translated_template = %{
              "content" => translated_content_map,
              "options" => options_translated,
              "type" => "quick_reply"
            }

          Map.put(
            acc,
            Integer.to_string(Map.get(language_code_map, lang_code)),
            translated_template
          )
      end
    end)
  end

  @spec translate_location_request(map(), map(), map(), non_neg_integer()) :: map()
  defp translate_location_request(content, active_languages, language_code_map, organization_id) do
    content_to_translate = [content["body"]["text"]]

    Enum.reduce(active_languages, %{}, fn {lang_name, lang_code}, acc ->
      translations =
        if lang_name == "English" do
          {:ok, content_to_translate}
        else
          GoogleTranslate.translate(content_to_translate, "English", lang_name,
            org_id: organization_id
          )
        end

      case translations do
        {:ok, [translated_text]} ->
          translated_template = %{
            "action" => content["action"],
            "body" => %{"text" => translated_text, "type" => content["body"]["type"]},
            "type" => content["type"]
          }

          Map.put(
            acc,
            Integer.to_string(Map.get(language_code_map, lang_code)),
            translated_template
          )
      end
    end)
  end

  @spec build_content_to_translate(map()) :: list
  def build_content_to_translate(content) do
    title = content["title"]
    body = content["body"]

    global_button_titles = Enum.map(content["globalButtons"], fn button -> button["title"] end)

    item_details =
      Enum.flat_map(content["items"], fn item ->
        option_titles_and_descriptions =
          Enum.flat_map(item["options"], fn option ->
            [option["title"], option["description"]]
          end)

        [item["title"], item["subtitle"]] ++ option_titles_and_descriptions
      end)

    [title, body] ++ global_button_titles ++ item_details
  end

  @spec translate_global_buttons([String.t()], [map()]) :: [map()]
  defp translate_global_buttons(global_buttons_translations, global_buttons) do
    Enum.zip(global_buttons_translations, global_buttons)
    |> Enum.map(fn {translated_title, button} ->
      Map.put(button, "title", translated_title)
    end)
  end

  @spec add_url_if_present(map(), map()) :: map()
  defp add_url_if_present(map, content) do
    if Map.has_key?(content["content"], "url") do
      Map.put(map, "url", content["content"]["url"])
    else
      map
    end
  end

  @spec do_options_translated(map(), list()) :: list()
  defp do_options_translated(content, options) do
    Enum.zip(Enum.map(content["options"], fn option -> option["type"] end), options)
    |> Enum.map(fn {type, title} -> %{"type" => type, "title" => title} end)
  end

  @spec do_items_translated(map(), list()) :: list()
  defp do_items_translated(content, items_translations) do
    chunk_sizes =
      Enum.map(content["items"], fn item ->
        2 + length(item["options"]) * 2
      end)

    translations_chunks =
      Enum.reduce(chunk_sizes, {[], items_translations}, fn chunk_size,
                                                            {acc, remaining_translations} ->
        {chunk, rest} = Enum.split(remaining_translations, chunk_size)
        {acc ++ [chunk], rest}
      end)
      |> elem(0)

    Enum.zip(content["items"], translations_chunks)
    |> Enum.map(fn {item, translated_item} ->
      [item_title, item_subtitle | options_translations] = translated_item

      options =
        options_translations
        |> Enum.chunk_every(2)
        |> Enum.zip(item["options"])
        |> Enum.map(fn {[option_title, option_description], option} ->
          %{
            "title" => option_title,
            "description" => option_description,
            "type" => option["type"]
          }
        end)

      %{
        "title" => item_title,
        "subtitle" => item_subtitle,
        "options" => options
      }
    end)
  end

  @spec content_to_translate(map(), String.t()) :: list()
  defp content_to_translate(content, label) do
    if Map.has_key?(content["content"], "caption") do
      [label, content["content"]["caption"], content["content"]["text"]] ++
        Enum.map(content["options"], fn option -> option["title"] end)
    else
      [label, content["content"]["text"]] ++
        Enum.map(content["options"], fn option -> option["title"] end)
    end
  end

  @spec create_translated_template(map(), String.t(), [String.t()]) :: map()
  defp create_translated_template(content, translated_label, remaining_translations) do
    if Map.has_key?(content["content"], "caption") do
      [caption, text | options] = remaining_translations
      options_translated = do_options_translated(content, options)

      translated_content_map =
        %{
          "header" => translated_label,
          "caption" => caption,
          "text" => text,
          "type" => content["content"]["type"]
        }
        |> add_url_if_present(content)

      %{
        "content" => translated_content_map,
        "options" => options_translated,
        "type" => "quick_reply"
      }
    else
      [text | options] = remaining_translations
      options_translated = do_options_translated(content, options)

      translated_content_map =
        %{
          "header" => translated_label,
          "text" => text,
          "type" => content["content"]["type"]
        }
        |> add_url_if_present(content)

      %{
        "content" => translated_content_map,
        "options" => options_translated,
        "type" => "quick_reply"
      }
    end
  end

  def export_interactive_template(interactive_template) do
    {:ok, translated_template} = translate_interactive_template(interactive_template)
    translations = translated_template.translations

    # Extract all unique attributes from the translations
    attributes =
      Enum.reduce(translations, MapSet.new(), fn {_lang, translation}, acc ->
        body_attributes = MapSet.new(["Body", "GlobalButtonTitle"])

        items_attributes =
          translation["items"]
          |> Enum.flat_map(fn item ->
            item_titles =
              MapSet.new([
                "ItemTitle 1",
                "ItemSubtitle 1"
              ])

            option_titles =
              item["options"]
              |> Enum.with_index()
              |> Enum.flat_map(fn {option, index} ->
                [
                  "OptionTitle 1.#{index + 1}",
                  "OptionDescription 1.#{index + 1}"
                ]
              end)
              |> MapSet.new()

            MapSet.union(item_titles, option_titles)
          end)
          |> MapSet.new()

        MapSet.union(acc, body_attributes)
        |> MapSet.union(items_attributes)
      end)
      |> MapSet.to_list()
      |> Enum.sort()

    language_codes = Map.keys(translations)
    language_name = get_language_name(language_codes)

    header = ["Attribute" | language_name]

    csv_rows =
      Enum.map(attributes, fn attribute ->
        row = [
          attribute
          | Enum.map(language_codes, fn lang ->
              case attribute do
                "Body" ->
                  translations[lang]["body"]

                "GlobalButtonTitle" ->
                  Enum.at(translations[lang]["globalButtons"], 0)["title"]

                _ ->
                  case Regex.run(
                         ~r/(ItemTitle|ItemSubtitle|OptionTitle|OptionDescription) (\d+)\.(\d+)/,
                         attribute
                       ) do
                    nil ->
                      ""

                    [_, "ItemTitle", item_num_str, _] ->
                      Enum.at(translations[lang]["items"], String.to_integer(item_num_str) - 1)[
                        "title"
                      ]

                    [_, "OptionTitle", item_num_str, option_num_str] ->
                      Enum.at(
                        Enum.at(translations[lang]["items"], String.to_integer(item_num_str) - 1)[
                          "options"
                        ],
                        String.to_integer(option_num_str) - 1
                      )["title"]

                    [_, "OptionDescription", item_num_str, option_num_str] ->
                      Enum.at(
                        Enum.at(translations[lang]["items"], String.to_integer(item_num_str) - 1)[
                          "options"
                        ],
                        String.to_integer(option_num_str) - 1
                      )["description"]
                  end
              end
            end)
        ]

        Enum.join(row, ",")
      end)

    csv_content =
      case csv_rows do
        [] -> ""
        list -> Enum.join(list, "\n")
      end

    file_path = "interactive_template.csv"

    case File.write(file_path, csv_content) do
      :ok -> {:ok, file_path}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_language_name(language_codes) do
    language_map = Settings.locale_id_map()
    Enum.map(language_codes, fn code -> Map.get(language_map, code) end)
  end
end
