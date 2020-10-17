defmodule Glific.CSV.File do
  @moduledoc """
  First implemenetation to convert sheets to flows using a menu structure and UUID
  """
  use Ecto.Schema

  alias Glific.{
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
  @spec read_csv_file(String.t()) :: map()
  def read_csv_file(file) do
    file
    |> Path.expand(__DIR__)
    |> File.stream!()
    |> CSV.decode()
    |> Enum.drop(3)
    |> Enum.map(fn {:ok, l} -> l end)
    |> parse_header()
    |> parse_rows(%{})
  end

  @doc """
  Given a header, extract the indexes of the language, menu and content
  items which helps us when parsing each row
  """
  @spec parse_header(list()) :: {list(), map()}
  def parse_header(rows) do
    header = hd(rows)

    meta_data = %{
      language: get_languages(header),
      menu: get_keyword_maps(header, "menu"),
      content: get_keyword_maps(header, "content")
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
  @spec get_keyword_maps(list(), String.t()) :: map()
  defp get_keyword_maps(header, key) do
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
          idx = Map.get(acc, menu_idx, %{})
          Map.put(acc, menu_idx, Map.put(idx, language, index))
        end
      end
    )
  end

  @spec parse_rows({list(), map()}, map()) :: map()
  defp parse_rows({rows, header_data}, summary) do
    rest = tl(rows)

    summary =
      summary
      |> Map.put(:header_data, header_data)
      |> Map.put(:menu, %{})
      |> Map.put(:content, %{})

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
      Enum.all?(rest, fn x -> x == "" end) -> summary
      true -> parse_valid_row(row, summary)
    end
  end

  defp parse_valid_row([num, _active, menu | _rest] = row, summary) do
    header_data = summary.header_data
    num = String.to_integer(num)

    menu_item = get_keyword_values(row, header_data.menu, false)
    content_item = get_keyword_values(row, header_data.content, true)

    summary =
      summary
      |> Map.update!(:menu, &Map.put(&1, num, menu_item))
      |> Map.update!(:content, &Map.put(&1, num, content_item))

    # if there is a menu entry here, lets process the menu items
    if menu == "" or is_nil(menu) or !String.starts_with?(menu, "menu:"),
      do: summary,
      else: create_menu_items(summary, menu)
  end

  defp create_menu_items(summary, menu) do
    m = String.split(menu, ":", trim: true)

    if length(m) > 1 do
      [_ | rest] = m

      Enum.reduce(
        rest,
        summary,
        fn i, acc -> merge_menu_items(acc, String.to_integer(i)) end
      )
    else
      summary
    end
  end

  defp merge_menu_items(summary, menu_idx) do
    # traverse the current summary.meny array
    # gather all elements of the menu_idx together, and make them
    # a subitem of the top level first entry
    # eliminate all other entries in the menu entry
    {menu, num, merged_item} =
      Enum.reduce(
        summary.menu,
        {%{}, 0, nil},
        fn {num, m}, {menu, merged_num, merged_item} ->
          if Map.has_key?(m, menu_idx) and !Map.has_key?(m[menu_idx], :merged) do
            m = Map.put(m, menu_idx, Map.put(m[menu_idx], :merged, true))

            {
              Map.put(menu, num, m),
              if(merged_item == nil, do: num, else: merged_num),
              merge_menu_item(merged_item, m, menu_idx)
            }
          else
            {Map.put(menu, num, m), merged_num, merged_item}
          end
        end
      )

    menu = Map.put(menu, num, merged_item)
    Map.put(summary, :menu, menu)
  end

  defp merge_menu_item(merged_item, item, menu_idx) do
    if merged_item == nil do
      merged_item = item
      sub_menu = Map.get(item, menu_idx)

      merged_item =
        if menu_idx == 1,
          do: Map.put(merged_item, menu_idx - 1, %{}),
          else: merged_item

      Map.update!(
        merged_item,
        menu_idx - 1,
        &Map.put(&1, :sub_menu, sub_menu)
      )
    else
      sub_menu = Map.get(item, menu_idx)

      Map.update!(
        merged_item,
        menu_idx - 1,
        fn value ->
          Map.update!(
            value,
            :sub_menu,
            &merge_menu_one(&1, sub_menu)
          )
        end
      )
    end
  end

  defp merge_menu_one(nil = _main, sub_menu),
    do: sub_menu

  defp merge_menu_one(main, sub_menu) do
    Map.merge(
      main,
      sub_menu,
      fn k, v1, v2 ->
        cond do
          k == :sub_menu and is_list(v1) -> v1 ++ [v2]
          k == :sub_menu -> [v1, v2]
          k == :merged -> v1
          # skip duplicates
          String.contains?(v1, v2) -> v1
          true -> v1 <> "\n" <> v2
        end
      end
    )
  end

  # maps are ordered for first 32 keys in elixir
  # lets use that for now
  defp get_keyword_values(row, header_map, merge) do
    # gather all the  items by id, grouped by language
    Enum.reduce(
      header_map,
      %{},
      fn {menu_idx, values}, acc ->
        value = get_keyword_value(row, values, %{})

        if merge,
          do:
            Map.merge(
              acc,
              value,
              fn _k, v1, v2 ->
                if v2 == "" or is_nil(v2),
                  do: v1,
                  else: v1 <> "\n" <> v2
              end
            ),
          else: Map.put(acc, menu_idx, value)
      end
    )
  end

  defp get_keyword_value(row, header_map, acc) do
    Enum.reduce(
      header_map,
      acc,
      fn {language, col}, acc ->
        Map.put(acc, language, Enum.at(row, col))
      end
    )
  end
end
