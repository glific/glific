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
  @spec gen_flow(Menu.t(), non_neg_integer) :: map()
  def gen_flow(root, organization_id) do
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
      },
      organization_id: organization_id
    }

    # first generate the nodes and localization for this node
    # then do it recursively for each of its menu items
    json_map = gen_flow_helper(json_map, root)

    json_map
    |> Map.put(:nodes, Enum.reverse(json_map.nodes))
    |> Map.delete(:organization_id)
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
          text: menu_content(node.content["en"], "en"),
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
          # we need to set this as null if there is no node with this UUID
          destination_uuid: node.uuids.router
        }
      ],
      actions: actions
    }

    exits =
      Enum.reverse(get_exits(node.content["en"], get_destination_uuids(node), node.uuids.node))

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
  @spec menu_content(map(), String.t()) :: any()
  defp menu_content(content, language) do
    template = Template.get_template(:menu, language)

    EEx.eval_string(
      template,
      language: language,
      items: indexed_content(content)
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
                else: language_content(content, node.menu_content.content, lang)

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
