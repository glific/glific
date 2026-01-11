defmodule Glific.TextToFlow do
  @moduledoc """
  Module to generate flow JSON from text prompts using OpenAI
  """

  alias Glific.OpenAI.ChatGPT
  alias Glific.Templates.InteractiveTemplates
  require Logger

  @prompt_id "pmpt_695f7036b0a4819585c74cbce8111743035b0031453d7321"
  @endpoint "https://api.openai.com/v1"
  @spec_version "14.3.0"
  @default_expire_minutes 10080

  @doc """
  Generate a flow from a text prompt using OpenAI's responses API

  ## Parameters
    - flow_name: Name for the generated flow
    - prompt: The user's text description of the flow they want to create
    - org_id: Organization ID for API key retrieval
    - flow_uuid: Optional UUID for the flow

  ## Returns
    - {:ok, glific_flow_json} on success
    - {:error, reason} on failure
  """
  @spec generate_flow(String.t(), String.t(), non_neg_integer(), String.t() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def generate_flow(flow_name, prompt, org_id, flow_uuid \\ nil) do
    with api_key <- Glific.get_open_ai_key(),
         {:ok, %{"flow" => flow_array}} <- call_openai_prompt_api(api_key, prompt) do
      # Convert simplified flow to full Glific format
      glific_json = convert_to_glific(flow_array, flow_name, flow_uuid, org_id)

      {:ok, glific_json}
    else
      {:error, reason} ->
        Logger.error("Error generating flow: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec call_openai_prompt_api(String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp call_openai_prompt_api(api_key, prompt) do
    url = @endpoint <> "/responses"

    prompt = "Create a flow json for this use case: #{prompt}"

    data = %{
      "input" => [
        %{
          "role" => "user",
          "content" => prompt
        }
      ],
      "prompt" => %{
        "id" => @prompt_id
      },
      "text" => %{
        "format" => %{
          "type" => "json_object"
        }
      }
    }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
    |> Tesla.post(url, data, opts: [adapter: [recv_timeout: 120_000]])
    |> handle_response()
  end

  @spec handle_response(tuple()) :: {:ok, map()} | {:error, String.t()}
  defp handle_response(response) do
    case response do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        content =
          body
          |> get_in(["output"])
          |> case do
            nil ->
              nil

            outputs when is_list(outputs) ->
              Enum.find_value(outputs, fn output ->
                get_in(output, ["content", Access.at(0), "text"])
              end)
          end

        case content do
          nil ->
            {:error, "No content in OpenAI response: #{inspect(body)}"}

          text ->
            case Jason.decode(text) do
              {:ok, flow_json} ->
                {:ok, flow_json}

              {:error, _} ->
                Logger.warning("Response is not valid JSON, returning as text")
                {:ok, %{"flow_data" => text}}
            end
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error = "Unexpected OpenAI response (#{status}): #{inspect(body)}"
        Logger.error(error)
        {:error, error}

      {:error, reason} ->
        error = "HTTP error calling OpenAI: #{inspect(reason)}"
        Logger.error(error)
        {:error, error}
    end
  end

  @doc """
  Convert simplified flow array to full Glific flow JSON

  ## Parameters
    - flow_array: List of simplified action maps
    - flow_name: Name of the flow
    - flow_uuid: UUID for the flow (optional, generates if not provided)
    - org_id: Organization ID for creating interactive templates

  ## Returns
    - Full Glific flow JSON map
  """
  @spec convert_to_glific(list(map()), String.t(), String.t() | nil, non_neg_integer()) :: map()
  def convert_to_glific(flow_array, flow_name, flow_uuid \\ nil, org_id) do
    flow_uuid = flow_uuid || Ecto.UUID.generate()
    nodes = build_nodes(flow_array, org_id)
    ui_nodes = build_ui_nodes(nodes)

    %{
      "_ui" => %{
        "nodes" => ui_nodes
      },
      "expire_after_minutes" => @default_expire_minutes,
      "language" => "base",
      "localization" => %{},
      "name" => flow_name,
      "nodes" => nodes,
      "spec_version" => @spec_version,
      "type" => "messaging",
      "uuid" => flow_uuid,
      "vars" => [flow_uuid]
    }
  end

  # Build all nodes from simplified flow array
  defp build_nodes(flow_array, org_id) do
    flow_array
    |> Enum.with_index()
    |> Enum.map(fn {action, index} ->
      next_index = index + 1
      has_next = next_index < length(flow_array)

      build_node(action, has_next, org_id)
    end)
    |> link_nodes()
  end

  # Build a single node based on action type
  defp build_node(%{"action" => "send_message", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "send_msg",
          "uuid" => Ecto.UUID.generate(),
          "text" => data["text"],
          "attachments" => [],
          "labels" => [],
          "quick_replies" => []
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          # Will be filled by link_nodes/1
          "destination_uuid" => nil
        }
      ],
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "send_quick_reply", "data" => data}, has_next, org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()

    # Build the interactive message JSON structure
    interactive_content = %{
      "type" => "quick_reply",
      "content" => %{
        "type" => "text",
        "header" => data["header"],
        "text" => data["text"] || ""
      },
      "options" =>
        Enum.map(data["options"] || [], fn option ->
          %{"type" => "text", "title" => option}
        end)
    }

    # Create interactive template in database
    {:ok, template} =
      InteractiveTemplates.create_interactive_template(%{
        label: data["header"] || "AI Generated #{node_uuid |> String.slice(0..7)}",
        type: "quick_reply",
        interactive_content: interactive_content,
        organization_id: org_id,
        language_id: 1
      })

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "send_interactive_msg",
          "uuid" => Ecto.UUID.generate(),
          "name" => data["header"],
          "id" => template.id,
          "text" => Jason.encode!(interactive_content),
          "attachment_url" => "",
          "attachment_type" => "",
          "labels" => []
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "wait_for_input", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()
    category_uuid = Ecto.UUID.generate()

    %{
      "uuid" => node_uuid,
      "actions" => [],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "router" => %{
        "type" => "switch",
        "wait" => %{"type" => "msg"},
        "operand" => "@input.text",
        "cases" => [],
        "categories" => [
          %{
            "uuid" => category_uuid,
            "name" => "All Responses",
            "exit_uuid" => exit_uuid
          }
        ],
        "default_category_uuid" => category_uuid,
        "result_name" => data["save_as"] || "result_#{node_uuid |> String.slice(0..7)}"
      },
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "add_label", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()

    labels =
      Enum.map(data["labels"] || [], fn label ->
        %{
          "name" => label,
          "uuid" => Ecto.UUID.generate()
        }
      end)

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "add_input_labels",
          "uuid" => Ecto.UUID.generate(),
          "labels" => labels
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "add_to_group", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "add_contact_groups",
          "uuid" => Ecto.UUID.generate(),
          "groups" => [
            %{
              "name" => data["group"],
              "type" => "group",
              "uuid" => Ecto.UUID.generate()
            }
          ]
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "set_contact_field", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "set_contact_field",
          "uuid" => Ecto.UUID.generate(),
          "field" => %{
            "key" => data["field"],
            "name" => data["field"]
          },
          "value" => data["value"]
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "set_result", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "set_run_result",
          "uuid" => Ecto.UUID.generate(),
          "name" => data["name"],
          "value" => data["value"],
          "category" => ""
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "open_ticket", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    success_exit_uuid = Ecto.UUID.generate()
    failure_exit_uuid = Ecto.UUID.generate()
    success_category_uuid = Ecto.UUID.generate()
    failure_category_uuid = Ecto.UUID.generate()

    assignee =
      if data["assignee"] do
        %{
          "name" => data["assignee"],
          "type" => "user",
          "uuid" => Ecto.UUID.generate()
        }
      else
        nil
      end

    action = %{
      "type" => "open_ticket",
      "uuid" => Ecto.UUID.generate(),
      "topic" => %{
        "name" => data["topic"],
        "uuid" => Ecto.UUID.generate()
      },
      "body" => data["body"] || "",
      "result_name" => "result"
    }

    action = if assignee, do: Map.put(action, "assignee", assignee), else: action

    %{
      "uuid" => node_uuid,
      "actions" => [action],
      "exits" => [
        %{
          "uuid" => success_exit_uuid,
          "destination_uuid" => nil
        },
        %{
          "uuid" => failure_exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "router" => %{
        "type" => "switch",
        "operand" => "@locals._new_ticket",
        "cases" => [
          %{
            "uuid" => Ecto.UUID.generate(),
            "type" => "has_text",
            "arguments" => [],
            "category_uuid" => success_category_uuid
          }
        ],
        "categories" => [
          %{
            "uuid" => success_category_uuid,
            "name" => "Success",
            "exit_uuid" => success_exit_uuid
          },
          %{
            "uuid" => failure_category_uuid,
            "name" => "Failure",
            "exit_uuid" => failure_exit_uuid
          }
        ],
        "default_category_uuid" => failure_category_uuid,
        "result_name" => "result"
      },
      "has_next" => has_next
    }
  end

  defp build_node(%{"action" => "wait", "data" => data}, has_next, _org_id) do
    node_uuid = Ecto.UUID.generate()
    exit_uuid = Ecto.UUID.generate()
    category_uuid = Ecto.UUID.generate()

    %{
      "uuid" => node_uuid,
      "actions" => [
        %{
          "type" => "wait_for_time",
          "uuid" => Ecto.UUID.generate(),
          "delay" => to_string(data["seconds"] || 0)
        }
      ],
      "exits" => [
        %{
          "uuid" => exit_uuid,
          "destination_uuid" => nil
        }
      ],
      "router" => %{
        "type" => "switch",
        "operand" => "@input.text",
        "cases" => [],
        "categories" => [
          %{
            "uuid" => category_uuid,
            "name" => "Completed",
            "exit_uuid" => exit_uuid
          }
        ],
        "default_category_uuid" => category_uuid
      },
      "has_next" => has_next
    }
  end

  defp build_node(action, _has_next, _org_id) do
    Logger.error("Unknown action type: #{inspect(action)}")
    raise "Unknown action type: #{inspect(action)}"
  end

  defp link_nodes(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, index} ->
      next_index = index + 1

      if node["has_next"] && next_index < length(nodes) do
        next_node = Enum.at(nodes, next_index)

        # Update first exit to point to next node
        updated_exits =
          node["exits"]
          |> Enum.with_index()
          |> Enum.map(fn {exit, exit_index} ->
            if exit_index == 0 do
              Map.put(exit, "destination_uuid", next_node["uuid"])
            else
              exit
            end
          end)

        node
        |> Map.put("exits", updated_exits)
        |> Map.delete("has_next")
      else
        node
        |> Map.delete("has_next")
      end
    end)
  end

  # Build UI positioning data for flow editor
  defp build_ui_nodes(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {node, index}, acc ->
      ui_type = determine_ui_type(node)

      # Calculate position (stack vertically with spacing)
      position = %{
        "left" => rem(index, 2) * 300 + 20,
        "top" => div(index, 2) * 180 + 20
      }

      ui_node = %{
        "type" => ui_type,
        "position" => position
      }

      # Add config if router exists
      ui_node = if node["router"], do: Map.put(ui_node, "config", %{}), else: ui_node

      Map.put(acc, node["uuid"], ui_node)
    end)
  end

  defp determine_ui_type(node) do
    cond do
      node["router"] && get_in(node, ["router", "wait", "type"]) == "msg" ->
        "wait_for_response"

      node["router"] && Enum.any?(node["actions"], &(&1["type"] == "wait_for_time")) ->
        "wait_for_time"

      node["router"] && Enum.any?(node["actions"], &(&1["type"] == "open_ticket")) ->
        "split_by_ticket"

      true ->
        "execute_actions"
    end
  end
end
