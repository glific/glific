defmodule Glific.CSV.Flow do
  @moduledoc """
  Given a CSV model, and a tracking shortcode, generate the json flow for the CSV
  incorporating the UUID's used in previous conversions. Store the latest UUID mapping
  back in the database
  """

  ## we need to put the default height and default width based on the content
  @default_height 300
  @default_offset 100
  @default_width 200

  alias Glific.{
    CSV.Menu,
    CSV.Template,
    Flows.FlowLabel
  }

  @doc """
  Given a menu + content structure, generate the flow for it that matches floweditor input
  """
  @spec gen_flow(Menu.t(), non_neg_integer, Keyword.t()) :: map()
  def gen_flow(root, organization_id, opts \\ []) do
    json_map = %{
      name: "LAHI Grade 9",
      expire_after_minutes: 10_080,
      spec_version: "13.1.0",
      type: "messaging",
      uuid: root.uuids.root,
      vars: [root.uuids.root],
      language: "base",
      nodes: [],
      localization: %{},
      _ui: %{
        nodes: %{}
      },
      organization_id: organization_id,
      opts: opts
    }

    # first generate the nodes and localization for this node
    # then do it recursively for each of its menu items
    json_map = gen_flow_helper(json_map, root)

    json_map
    |> Map.put(:nodes, Enum.reverse(json_map.nodes))
    |> Map.delete(:organization_id)
    |> Map.delete(:opts)
  end

  @spec gen_flow_helper(map(), Menu.t()) :: map()
  defp gen_flow_helper(json_map, node) do
    if Enum.empty?(node.sub_menus) do
      gen_flow_content(json_map, node)
    else
      gen_flow_menu(json_map, node)
    end
  end

  defp add_label(actions, %{label: nil}, _organization_id), do: actions

  defp add_label(actions, %{label: name}, organization_id) do
    {:ok, label} =
      FlowLabel.get_or_create_flow_label(%{name: name, organization_id: organization_id})

    [
      %{
        labels: [
          %{
            name: name,
            uuid: label.uuid
          }
        ],
        type: "add_input_labels",
        uuid: Ecto.UUID.generate()
      }
      | actions
    ]
  end

  # this is a menu node
  # generate the message and the localization
  # call gen_flow_helper on each sub_menu
  @spec gen_flow_menu(map(), Menu.t()) :: map()
  defp gen_flow_menu(json_map, node) do
    actions =
      [
        %{
          uuid: node.uuids.action,
          quick_replies: [],
          attachments: [],
          text: menu_content(node.content["en"], "en", node, json_map),
          type: "send_msg"
        }
      ]
      |> add_label(node, json_map.organization_id)

    node_json = %{
      uuid: node.uuids.node,
      exits: [
        %{
          uuid: node.uuids.exit,
          destination_uuid: node.uuids.router
        }
      ],
      actions: actions
    }

    menu_content =
      node.content["en"]
      |> indexed_content(node, json_map)

    exits = get_exits(menu_content, get_destination_uuids(node), node.uuids.node)

    cases = get_cases(menu_content)
    {categories, default_category_uuid} = get_categories(menu_content, exits, cases)

    router_json = %{
      uuid: node.uuids.router,
      actions: [],
      exits: Map.values(exits),
      router: %{
        cases: Map.values(cases),
        wait: %{type: "msg"},
        operand: "@input.text",
        categories: Map.values(categories),
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
    json_map = add_ui(json_map, node, :content)

    nodes =
      json_map._ui.nodes
      |> Map.put(
        node.uuids.router,
        %{
          position: %{
            top: node.level * @default_height,
            left: node.position * @default_width + @default_offset
          },
          config: %{
            cases: %{}
          },
          type: "wait_for_response"
        }
      )

    put_in(json_map, [:_ui, :nodes], nodes)
  end

  defp add_back_main_uuids(acc, node),
    do:
      acc
      |> Map.put(8, node.uuids.root)
      |> Map.put(9, node.uuids.parent)

  defp get_destination_uuids(node) do
    # collect all the destination uuids from the sub_menu
    node.sub_menus
    |> Enum.with_index(1)
    |> Enum.reduce(
      %{},
      fn {s, idx}, acc -> Map.put(acc, idx, s.uuids.node) end
    )
    # add the back and main menu uuids
    |> add_back_main_uuids(node)
  end

  defp indexed_content(content, node, json_map) do
    content
    |> Map.values()
    |> Enum.with_index(1)
    |> add_back_case(node, Keyword.get(json_map.opts, :back_menu_item, false))
    |> add_main_case(node, Keyword.get(json_map.opts, :main_menu_item, false))
  end

  defp get_exits(menu_content, destination_uuids, node_uuid) do
    exits =
      menu_content
      |> Enum.reduce(
        %{},
        fn {_str, idx}, acc ->
          Map.put(
            acc,
            idx,
            %{uuid: Ecto.UUID.generate(), destination_uuid: Map.get(destination_uuids, idx)}
          )
        end
      )

    # also add Other (and soon no response)
    exits
    |> Map.put(
      10,
      %{uuid: Ecto.UUID.generate(), destination_uuid: node_uuid}
    )
  end

  defp get_cases(menu_content) do
    menu_content
    |> Enum.reduce(
      %{},
      fn {_str, index}, acc ->
        Map.put(
          acc,
          index,
          %{
            arguments: [to_string(index)],
            type: "has_number_eq",
            uuid: Ecto.UUID.generate(),
            category_uuid: Ecto.UUID.generate()
          }
        )
      end
    )
  end

  defp add_main_case(content, _node, false), do: content
  defp add_main_case(content, %{level: level} = _node, _) when level <= 1, do: content

  defp add_main_case(content, _node, true) do
    content ++ [{"Press 9 to return to Main Menu", 9}]
  end

  defp add_back_case(content, _node, false), do: content
  defp add_back_case(content, %{level: level} = _node, _) when level <= 2, do: content

  defp add_back_case(content, _node, true) do
    content ++ [{"Press 8 to return to previous menu", 8}]
  end

  defp get_categories(menu_content, exits, cases) do
    categories =
      menu_content
      |> Enum.reduce(
        %{},
        fn {_str, index}, acc ->
          Map.put(
            acc,
            index,
            %{
              uuid: Map.get(cases, index).category_uuid,
              name: to_string(index),
              exit_uuid: Map.get(exits, index).uuid
            }
          )
        end
      )

    # Add Other category
    default_category_uuid = Ecto.UUID.generate()

    categories =
      Map.put(
        categories,
        10,
        %{
          uuid: default_category_uuid,
          name: "Other",
          exit_uuid: Map.get(exits, 10).uuid
        }
      )

    {categories, default_category_uuid}
  end

  # this is a content node
  # generate the message and the localization
  @spec gen_flow_content(map(), Menu.t()) :: map()
  defp gen_flow_content(json_map, node) do
    actions =
      [
        %{
          uuid: node.uuids.action,
          attachmnents: [],
          quick_replies: [],
          text: language_content(node.content["en"], node.menu_content.content, "en"),
          type: "send_msg"
        }
      ]
      |> add_label(node, json_map.organization_id)

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
      actions: actions
    }

    json_map
    |> Map.update!(:nodes, fn n -> [node_json | n] end)
    |> add_localization(node, :content)
    |> add_ui(node, :content)
  end

  # Get the content for language
  @spec language_content(map(), map(), String.t()) :: any()
  defp language_content(content, menu_content, language) do
    template = Template.get_template(:content, language)

    EEx.eval_string(
      template,
      language: language,
      items: content,
      menu_item: Map.get(menu_content, language)
    )
  end

  # get the content for a menu and language
  @spec menu_content(map(), String.t(), map(), map()) :: any()
  defp menu_content(content, language, node, json_map) do
    template = Template.get_template(:menu, language)

    EEx.eval_string(
      template,
      language: language,
      items: indexed_content(content, node, json_map)
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
                do: menu_content(content, lang, node, json_map),
                else: language_content(content, node.menu_content.content, lang)

            Map.update(
              acc,
              lang,
              %{
                node.uuids.action => %{text: [text]}
              },
              fn l -> Map.put(l, node.uuids.action, %{text: [text]}) end
            )
          end
        end
      )

    Map.put(json_map, :localization, localization)
  end
end
