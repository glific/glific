defmodule Glific.CSV.Flow do
  @moduledoc """
  Given a CSV model, and a tracking shortcode, generate the json flow for the CSV
  incorporating the UUID's used in previous conversions. Store the latest UUID mapping
  back in the database
  """

     ## we need to put the default height and default width based on the content
    @default_height  400
    @default_width  200

  alias Glific.{
    CSV.Menu
  }

  @doc """
  Given a menu + content structure, generate the flow for it that matches floweditor input
  """
  @spec gen_flow(Menu.t()) :: map()
  def gen_flow(root) do
    json_map = %{
      name: "LAHI Grade 9",
      expire_after_minutes: 10_080,
      spec_version: "13.1.0",
      type: "messaging",
      uuid: root.uuids.main,
      vars: [root.uuids.main],
      language: "base",
      nodes: [],
      localization: %{},
      _ui: %{
        nodes: %{}
      }
    }

    # first generate the nodes and localization (and later _ui) for
    # this node, then do it recursively for each of its menu items
    json_map = gen_flow_helper(json_map, root)

    Map.put(json_map, :nodes, Enum.reverse(json_map.nodes))
  end

  @spec gen_flow_helper(map(), Menu.t()) :: map()
  defp gen_flow_helper(json_map, node) do
    if Enum.empty?(node.sub_menus) do
      gen_flow_content(json_map, node)
    else
      gen_flow_menu(json_map, node)
    end
  end

  # this is a menu node
  # generate the message and the localization
  # call gen_flow_helper on each sub_menu
  @spec gen_flow_menu(map(), Menu.t()) :: map()
  defp gen_flow_menu(json_map, node) do
    node_json = %{
      uuid: node.uuids.node,
      exits: [
        %{
          uuid: node.uuids.exit,
          # At some stage for all content nodes, we'll basically go back to main menu
          # for any key pressed
          # we need to set this as null if there is no node with this UUID
          destination_uuid: node.uuids.router
        }
      ],
      actions: [
        %{
          uuid: node.uuids.action,
          quick_replies: [],
          attachments: [],
          text: menu_content(node.content["en"], "en"),
          type: "send_msg"
        }
      ]
    }

    exits = Enum.reverse(get_exits(node.content["en"], get_destination_uuids(node), node.uuids.node))
    cases = Enum.reverse(get_cases(node.content["en"]))
    {categories, default_category_uuid} = get_categories(node.content["en"], exits, cases)

    router_json = %{
      uuid: node.uuids.router,
      actions: [],
      exits: exits,
      router: %{
        cases: [cases],
        wait: %{type: "msg"},
        operand: "@input.text",
        categories: categories,
        default_category_uuid: default_category_uuid,
        type: "switch"
      }
    }

    json_map =
      json_map
      |> Map.update!(:nodes, fn n -> [router_json, node_json | n] end)
      |> add_localization(node, :menu)
      |> add_ui(node, :menu)

    # now go thru all the sub_menu and call json_map for each of them
    Enum.reduce(
      node.sub_menus,
      json_map,
      fn menu, acc -> gen_flow_helper(acc, menu) end
    )
  end

  defp add_ui(json_map, node, :content) do
    nodes =
      json_map._ui.nodes
      |> Map.put(
        node.uuids.node,
        %{
          position: %{
            top: node.level * @default_height,
            left: node.position * @default_width
          },
          type: "execute_actions"
        }
      )

    put_in(json_map, [:_ui, :nodes], nodes)
  end

  defp add_ui(json_map, node, :menu) do
    nodes =
      json_map._ui.nodes
      |> Map.put(
        node.uuids.router,
        %{
          position: %{
            top: node.level * @default_height + @default_width,
            left: node.position * @default_width
          },
          config: %{
            cases: %{}
          },
          type: "wait_for_response"
        }
      )

    # also add the content node
    json_map
    |> add_ui(node, :content)
    |> put_in([:_ui, :nodes], nodes)
  end

  defp get_destination_uuids(node) do
    # collect all the destination uuids from the sub_menu
    node.sub_menus
    |> Enum.reduce(
      [],
      fn s, acc -> [s.uuids.node | acc] end
    )
    |> Enum.reverse()
  end

  defp indexed_content(content),
    do: content |> Map.values() |> Enum.with_index(1)

  defp get_exits(content, destination_uuids, node_uuid) do
    exits =
      content
      |> indexed_content()
      |> Enum.reduce(
        [],
        fn {_str, idx}, acc ->
          [
            %{uuid: Ecto.UUID.generate(), destination_uuid: Enum.at(destination_uuids, idx - 1)}
            | acc
          ]
        end
      )

    # also add Other (and soon no response)
    [%{uuid: Ecto.UUID.generate(), destination_uuid: node_uuid} | exits]
  end

  defp get_cases(content) do
    content
    |> indexed_content()
    |> Enum.reduce(
      [],
      fn {_str, index}, acc ->
        [
          %{
            arguments: [to_string(index)],
            type: "has_number_eq",
            uuid: Ecto.UUID.generate(),
            category_uuid: Ecto.UUID.generate()
          }
          | acc
        ]
      end
    )
  end

  defp get_categories(content, exits, cases) do
    categories =
      content
      |> indexed_content()
      |> Enum.reduce(
        [],
        fn {_str, index}, acc ->
          [
            %{
              uuid: Enum.at(cases, index - 1).category_uuid,
              name: to_string(index),
              exit_uuid: Enum.at(exits, index - 1).uuid
            }
            | acc
          ]
        end
      )

    # Add Other category
    default_category_uuid = Ecto.UUID.generate()

    categories = [
      %{
        uuid: default_category_uuid,
        name: "Other",
        exit_uuid: List.last(exits).uuid
      }
      | categories
    ]

    {Enum.reverse(categories), default_category_uuid}
  end

  # this is a content node
  # generate the message and the localization
  @spec gen_flow_content(map(), Menu.t()) :: map()
  defp gen_flow_content(json_map, node) do
    node_json = %{
      uuid: node.uuids.node,
      exits: [
        %{
          uuid: node.uuids.exit,
          # At some stage for all content nodes, we'll basically go back to main menu
          # for any key pressed
          destination_uuid: nil
        }
      ],
      actions: [
        %{
          uuid: node.uuids.action,
          quick_replies: [],
          text: language_content(node.content["en"], "en")
        }
      ]
    }

    json_map
    |> Map.update!(:nodes, fn n -> [node_json | n] end)
    |> add_localization(node, :content)
    |> add_ui(node, :content)
  end

  # Get the content for language
  @spec language_content(map(), String.t()) :: String.t()
  defp language_content(content, _language) do
    Enum.join(Map.values(content), "\n")
  end

  # get the content for a menu and language
  @spec menu_content(map(), String.t()) :: String.t()
  defp menu_content(content, _language) do
    content
    |> indexed_content()
    |> Enum.reduce(
      "",
      fn {str, index}, acc ->
        "#{acc} #{to_string(index)}. #{str}\n"
      end
    )
  end

  @spec add_localization(map(), Menu.t(), atom()) :: map()
  defp add_localization(json_map, node, type) do
    localization =
      node.content
      |> Enum.reduce(
        json_map.localization,
        fn {lang, content}, acc ->
          if lang == "en" do
            acc
          else
            text =
              if type == :menu,
                do: menu_content(content, lang),
                else: language_content(content, lang)

            Map.update(
              acc,
              lang,
              %{
                lang => %{
                  node.uuids.action => %{text: [text]}
                }
              },
              fn l -> Map.put(l, node.uuids.action, %{text: [text]}) end
            )
          end
        end
      )

    Map.put(json_map, :localization, localization)
  end
end
