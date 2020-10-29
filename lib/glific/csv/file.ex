defmodule Glific.CSV.File do
  @moduledoc """
  First implemenetation to convert sheets to flows using a menu structure and UUID
  """
  use Ecto.Schema

  alias Glific.{
    CSV.Content,
    CSV.Flow,
    CSV.Menu,
    Partners.Organization
  }

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          contents: String.t() | nil,
          uuid_map: map() | nil,
          main_menu: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "csv_files" do
    field :name, :string

    field :contents, :string

    field :uuid_map, :map

    field :main_menu, :map, virtual: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Read a csv file, and split it up into a bunch of tuples that we are interested in. Assuming
  that the csv file is valid for now
  """
  @spec process_csv_file(String.t(), String.t(), non_neg_integer) :: map()
  def process_csv_file(file, output, organization_id) do
    summary =
      file
      |> Path.expand(__DIR__)
      |> File.stream!()
      |> CSV.decode()
      |> Enum.drop(3)
      |> Enum.map(fn {:ok, l} -> l end)
      |> parse_header()
      |> parse_rows(%{})

    json_map = Flow.gen_flow(summary.menus[0], organization_id, [main_menu_item: true, back_menu_item: false])
    {:ok, json} = Jason.encode_to_iodata(json_map, pretty: true)

    :ok =
      output
      |> Path.expand(__DIR__)
      |> File.write(json)

    summary
    |> Map.put(:root, summary.menus[0])
    |> Map.put(:json_map, json_map)
    |> Map.delete(:menus)
  end

  @doc """
  Given a header, extract the indexes of the language, menu and content
  items which helps us when parsing each row
  """
  @spec parse_header(list()) :: {list(), map()}
  def parse_header([header | _rest] = rows) do
    meta_data = %{
      language: get_languages(header),
      menu: get_keyword_maps(header, "menu"),
      content: get_keyword_maps(header, "content"),
      label: get_keyword_maps(header, "label", true),
    }

    {rows, meta_data}
  end

  @spec get_languages(list()) :: map()
  defp get_languages(header) do
    header
    |> Enum.reduce(
      %{},
      fn r, acc ->
        s = String.split(r, ":", parts: 2, trim: true)

        if length(s) != 2,
          do: acc,
          else: Map.put(acc, hd(s), true)
      end
    )
  end

  # get the mapping of menu and content items to their column position
  @spec get_keyword_maps(list(), String.t(), boolean()) :: map()
  defp get_keyword_maps(header, key, ignore_language \\ false) do
    header
    |> Enum.with_index()
    |> Enum.reduce(
      %{},
      fn {r, index}, acc ->
        s = String.split(r, ":", parts: 3, trim: true)

        if length(s) != 3 or Enum.at(s, 1) != key do
          acc
        else
          [language, _, menu_idx] = s
          menu_idx = String.to_integer(menu_idx)

          if ignore_language do
            Map.put(acc, menu_idx, index)
          else
            idx = Map.get(acc, menu_idx, %{})
            Map.put(acc, menu_idx, Map.put(idx, language, index))
          end
        end
      end
    )
  end

  @spec parse_rows({list(), map()}, map()) :: map()
  defp parse_rows({rows, header_data}, summary) do
    rest = tl(rows)

    # lets hardcode this for the flow, to make it easier to import
    # into our db and hence flow-editor
    # root_uuid = Ecto.UUID.generate()
    {:ok, root_uuid} = Ecto.UUID.cast("8a67330c-8cf6-498f-93fb-d771e675ff22")

    root = %Menu{
      uuids: %{
        node: Ecto.UUID.generate(),
        action: Ecto.UUID.generate(),
        exit: Ecto.UUID.generate(),
        router: Ecto.UUID.generate(),
        label: Ecto.UUID.generate(),
        parent: nil,
        root: root_uuid
      },
      sr_no: 0,
      level: 0,
      position: 0,
      content: %{},
      menu_content: nil,
      content_item: nil,
      sub_menus: []
    }

    summary =
      summary
      |> Map.put(:header_data, header_data)
      |> Map.put(:menus, %{0 => root})
      |> Map.put(:positions, %{0 => 0, 1 => 0})

    rest
    |> Enum.reduce(
      summary,
      fn r, acc ->
        parse_row(r, acc)
      end
    )
  end

  defp parse_row([_num, active | rest] = row, summary) do
    cond do
      active == "FALSE" -> summary
      Enum.all?(rest, fn x -> x == "" or is_nil(x) end) -> summary
      true -> parse_valid_row(row, summary)
    end
  end

  defp parse_valid_row([num, _active | _rest] = row, summary) do
    header_data = summary.header_data
    num = String.to_integer(num)

    menu_opts = %{
      sr_no: num,
      level: 0,
      position: 0
    }

    menu_content = content_item(row, header_data.menu, menu_opts)
    leaf_menu_idx = Enum.max(Map.keys(menu_content))

    # get the labels
    labels = get_labels(row, header_data.label)

    # initialize position of content items
    content_opts = %{
      sr_no: num,
      # since we start numbering from 0 internally
      level: leaf_menu_idx * 2 + 1,
      position: Map.get(summary.positions, leaf_menu_idx, 0)
    }

    content_item = content_item(row, header_data.content, content_opts)
    positions = Map.put(summary.positions, leaf_menu_idx, content_opts.position + 1)
    summary = Map.put(summary, :positions, positions)

    # create menu entries for each of the menu_content items
    # in sorted order
    Enum.reduce(
      menu_content,
      summary,
      fn {idx, menu}, summary ->
        {item, content, level, position, summary} =
          if idx == leaf_menu_idx do
            c = hd(Map.values(content_item))
            {content_item, build_content_map(content_item), c.level, c.position, summary}
          else
            position = Map.get(summary.positions, idx, 0)
            positions = Map.put(summary.positions, idx, position + 1)
            summary = Map.put(summary, :positions, positions)
            {nil, %{}, summary.menus[idx - 1].level + 2, position, summary}
          end

        sub_menu =
          create_menu(
            summary.menus[0].uuids.node,
            summary.menus[idx - 1].uuids.node,
            sr_no: num,
            label: labels[idx],
            level: level,
            position: position,
            menu_content: menu,
            content_item: item,
            content: content
          )

        # keep track of the latest menu for this level
        # we append the next higher level submenus here
        parent_menu =
          summary.menus[idx - 1]
          |> Map.update(:sub_menus, [sub_menu], fn m -> m ++ [sub_menu] end)
          |> Map.update!(:content, fn c -> merge_menu_content(c, sub_menu.menu_content) end)

        menus =
          summary.menus
          |> Map.put(idx, sub_menu)
          |> Map.put(idx - 1, parent_menu)
          |> update_ancestors(parent_menu, idx - 2)

        Map.put(summary, :menus, menus)
      end
    )
  end

  defp update_ancestors(menus, _leaf, idx) when idx < 0, do: menus

  defp update_ancestors(menus, leaf, idx) do
    # update the parent at the leaf id
    parent = Map.get(menus, idx)
    parent = Map.update!(parent, :sub_menus, fn m -> List.update_at(m, -1, fn _l -> leaf end) end)
    menus = Map.put(menus, idx, parent)

    # do it for its ancestor also
    update_ancestors(menus, parent, idx - 1)
  end

  defp create_menu(root, parent, attrs) do
    defaults = [
      uuids: %{
        node: Ecto.UUID.generate(),
        action: Ecto.UUID.generate(),
        exit: Ecto.UUID.generate(),
        router: Ecto.UUID.generate(),
        label: Ecto.UUID.generate(),
        parent: parent,
        root: root
      },
      position: 0,
      level: 0,
      sub_menus: [],
      content_items: []
    ]

    struct(Menu, Keyword.merge(defaults, attrs))
  end

  defp get_labels(row, header_map) do
    Enum.reduce(
      header_map,
      %{},
      fn {idx, col}, acc -> Map.put(acc, idx, Enum.at(row, col)) end
    )
  end

  # get the content items from the row, and create the content structure
  # return as an array of content items
  defp content_item(row, header_map, opts) do
    Enum.reduce(
      header_map,
      %{},
      fn {idx, values}, acc ->
        content = get_content_value(row, values)

        if empty?(content) do
          acc
        else
          Map.put(acc, idx, %Content{
            sr_no: opts.sr_no,
            level: opts.level,
            position: opts.position,
            content: content
          })
        end
      end
    )
  end

  defp empty?(content),
    do: Enum.all?(content, fn {_k, v} -> v == "" or is_nil(v) end)

  defp get_content_value(row, header_map) do
    Enum.reduce(
      header_map,
      %{},
      fn {language, col}, acc ->
        Map.put(acc, language, Enum.at(row, col))
      end
    )
  end

  defp build_content_map(content) do
    Enum.reduce(
      content,
      %{},
      fn {idx, cont}, acc ->
        merge_content_map(idx, cont, acc)
      end
    )
  end

  defp merge_content_map(idx, cont, acc) do
    Enum.reduce(
      cont.content,
      acc,
      fn {lang, text}, acc ->
        Map.update(
          acc,
          lang,
          %{idx => text},
          fn l -> Map.put(l, idx, text) end
        )
      end
    )
  end

  defp merge_menu_content(main_menu, sub_menu) do
    Enum.reduce(
      sub_menu.content,
      main_menu,
      fn {lang, text}, acc ->
        Map.update(acc, lang, %{sub_menu.sr_no => text}, fn m ->
          Map.put(m, sub_menu.sr_no, text)
        end)
      end
    )
  end
end
