defmodule Glific.FilesearchTest do
  @moduledoc """
  Tests for public filesearch APIs
  """

  alias Glific.{
    Assistants,
    Assistants.AssistantConfigVersion,
    Partners,
    Repo
  }

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Ecto.Query

  load_gql(
    :create_assistant,
    GlificWeb.Schema,
    "assets/gql/assistants/create_assistant.gql"
  )

  load_gql(
    :delete_assistant,
    GlificWeb.Schema,
    "assets/gql/assistants/delete_assistant.gql"
  )

  load_gql(
    :update_assistant,
    GlificWeb.Schema,
    "assets/gql/assistants/update_assistant.gql"
  )

  load_gql(
    :assistant,
    GlificWeb.Schema,
    "assets/gql/assistants/assistant_by_id.gql"
  )

  load_gql(
    :assistants,
    GlificWeb.Schema,
    "assets/gql/assistants/list_assistants.gql"
  )

  load_gql(
    :count_assistants,
    GlificWeb.Schema,
    "assets/gql/assistants/count_assistants.gql"
  )

  load_gql(
    :list_models,
    GlificWeb.Schema,
    "assets/gql/filesearch/list_models.gql"
  )

  test "update assistant", attrs do
    enable_kaapi(%{organization_id: attrs.organization_id})

    Partners.organization(attrs.organization_id)

    {unified_assistant, _} =
      create_unified_assistant(%{
        organization_id: attrs.organization_id,
        name: "new assistant",
        kaapi_uuid: "asst_abc_upd"
      })

    Tesla.Mock.mock(fn
      %{method: :post, url: "This is not a secret/api/v1/configs/asst_abc_upd/versions"} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{id: "config-version-id-1", version: 1}}
        }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:update_assistant, attrs.user,
        variables: %{
          "input" => %{
            "name" => "new assistant",
            "instructions" => "You are a helpful assistant",
            "model" => "gpt-4o",
            "temperature" => 1.0
          },
          "id" => unified_assistant.id
        }
      )

    assert query_data.data["updateAssistant"]["assistant"]["assistant_id"] ==
             unified_assistant.kaapi_uuid

    # updating with some input variables
    {:ok, query_data} =
      auth_query_gql_by(:update_assistant, attrs.user,
        variables: %{
          "input" => %{
            "name" => "assistant2",
            "instructions" => "no instruction",
            "temperature" => 1.8
          },
          "id" => unified_assistant.id
        }
      )

    new_config_version =
      AssistantConfigVersion
      |> where([acv], acv.assistant_id == ^unified_assistant.id)
      |> order_by([acv], desc: acv.version_number)
      |> limit(1)
      |> Repo.one()

    assert get_in(new_config_version.settings, ["temperature"]) == 1.8

    assert %{"name" => "assistant2"} =
             query_data.data["updateAssistant"]["assistant"]

    assert query_data.data["updateAssistant"]["assistant"]["assistant_id"] ==
             unified_assistant.kaapi_uuid
  end

  test "get assistant", attrs do
    {assistant, _} =
      create_unified_assistant(%{
        organization_id: attrs.organization_id,
        name: "new assistant",
        kaapi_uuid: "asst_abc"
      })

    {:ok, query_data} =
      auth_query_gql_by(:assistant, attrs.user,
        variables: %{
          "id" => assistant.id
        }
      )

    assert %{"name" => "new assistant"} =
             query_data.data["assistant"]["assistant"]

    # Trying to fetch invalid assistant
    {:ok, query_data} =
      auth_query_gql_by(:assistant, attrs.user,
        variables: %{
          "id" => 0
        }
      )

    assert length(query_data.data["assistant"]["errors"]) == 1
  end

  test "get assistant with vector store", attrs do
    {assistant, _} =
      create_unified_assistant(%{
        organization_id: attrs.organization_id,
        name: "assistant with vs",
        kaapi_uuid: "asst_vs",
        kb_name: "Test KB",
        knowledge_base_version_id: "vs_test_123",
        files: %{
          "file_1" => %{
            "filename" => "test.pdf",
            "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now())
          }
        },
        size: 2_048
      })

    {:ok, query_data} =
      auth_query_gql_by(:assistant, attrs.user,
        variables: %{
          "id" => assistant.id
        }
      )

    assistant_data = query_data.data["assistant"]["assistant"]
    assert assistant_data["name"] == "assistant with vs"

    vector_store = assistant_data["vector_store"]
    assert vector_store["name"] == "Test KB"
    assert vector_store["status"] == "completed"
    assert vector_store["legacy"] == true
    assert vector_store["size"] == "2.0 KB"
    assert length(vector_store["files"]) == 1
    assert hd(vector_store["files"])["name"] == "test.pdf"
  end

  test "list assistants", attrs do
    # empty assistants
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user, variables: %{})

    assert result.data["Assistants"] == []

    create_unified_assistant(%{
      organization_id: attrs.organization_id,
      name: "new assistant",
      kaapi_uuid: "asst_abc"
    })

    create_unified_assistant(%{
      organization_id: attrs.organization_id,
      name: "new assistant 2",
      kaapi_uuid: "asst_abc2",
      kb_name: "new KB"
    })

    # fetch all
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user, variables: %{})

    assert length(result.data["Assistants"]) == 2

    # live_version_number is nil when version_number not set on config version
    assert Enum.all?(result.data["Assistants"], fn a ->
             Map.has_key?(a, "live_version_number")
           end)

    # limit 1
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user,
        variables: %{
          "opts" => %{
            "limit" => 1
          }
        }
      )

    assert length(result.data["Assistants"]) == 1

    {assistant3, _} =
      create_unified_assistant(%{
        organization_id: attrs.organization_id,
        name: "new assistant 3",
        kaapi_uuid: "asst_xyz",
        kb_name: "Third KB"
      })

    # limit 1, offset 2
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user,
        variables: %{
          "opts" => %{
            "limit" => 1,
            "offset" => 2
          }
        }
      )

    date = DateTime.utc_now() |> DateTime.add(-2 * 86_400)

    Assistants.Assistant
    |> where([a], a.id == ^assistant3.id)
    |> update([a], set: [inserted_at: ^date])
    |> Repo.update_all([])

    assert length(result.data["Assistants"]) == 1

    # limit 1, default asc by inserted_at
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user,
        variables: %{
          "opts" => %{
            "limit" => 1
          }
        }
      )

    assert %{"name" => "new assistant 3"} = List.first(result.data["Assistants"])

    # search by name
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user,
        variables: %{
          "filter" => %{
            "name" => "3"
          }
        }
      )

    assert %{"name" => "new assistant 3"} = List.first(result.data["Assistants"])
  end

  test "count assistants", attrs do
    {:ok, result} = auth_query_gql_by(:count_assistants, attrs.user, variables: %{})
    assert result.data["countAssistants"] == 0

    create_unified_assistant(%{
      organization_id: attrs.organization_id,
      name: "assistant A",
      kaapi_uuid: "asst_count_1",
      kb_name: "KB count 1"
    })

    create_unified_assistant(%{
      organization_id: attrs.organization_id,
      name: "assistant B",
      kaapi_uuid: "asst_count_2",
      kb_name: "KB count 2"
    })

    {:ok, result} = auth_query_gql_by(:count_assistants, attrs.user, variables: %{})
    assert result.data["countAssistants"] == 2

    {:ok, result} =
      auth_query_gql_by(:count_assistants, attrs.user,
        variables: %{"filter" => %{"name" => "assistant A"}}
      )

    assert result.data["countAssistants"] == 1
  end

  test "list_models, success api response", attrs do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: [
              %{
                owned_by: "project-tech4dev",
                id: "gpt-4o"
              },
              %{
                owned_by: "system",
                id: "gpt-4o"
              },
              %{
                owned_by: "system",
                id: "dalle-e"
              }
            ]
          }
        }
    end)

    {:ok, result} =
      auth_query_gql_by(:list_models, attrs.user, variables: %{})

    assert length(result.data["ListOpenaiModels"]) == 1
  end

  test "list_models, openai api failure", attrs do
    # If api is failed from openAI, we just send the default model which is gpt-4o
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 408,
          body: %{
            error: %{
              message: "timeout"
            }
          }
        }
    end)

    {:ok, result} =
      auth_query_gql_by(:list_models, attrs.user, variables: %{})

    assert length(result.data["ListOpenaiModels"]) == 1
  end

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_test_key"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_test_key"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
  end

  defp create_unified_assistant(attrs) do
    defaults = %{
      name: "Test Assistant",
      kaapi_uuid: "asst_test_#{:rand.uniform(10000)}",
      model: "gpt-4o",
      instructions: "You are a helpful assistant",
      temperature: 1.0,
      status: :ready,
      kb_name: "Default KB",
      knowledge_base_version_id: "vs_default_#{:rand.uniform(10000)}",
      llm_service_id: "vs_default_#{:rand.uniform(10000)}",
      files: %{},
      kb_status: :completed,
      size: 0
    }

    attrs = Map.merge(defaults, attrs)
    org_id = attrs.organization_id

    {:ok, assistant} =
      %Assistants.Assistant{}
      |> Assistants.Assistant.changeset(%{
        name: attrs.name,
        organization_id: org_id,
        kaapi_uuid: attrs.kaapi_uuid
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        organization_id: org_id,
        provider: "openai",
        model: attrs.model,
        prompt: attrs.instructions,
        settings: %{"temperature" => attrs.temperature},
        status: attrs.status
      })
      |> Repo.insert()

    link_knowledge_base(config_version, attrs)

    {:ok, assistant} =
      assistant
      |> Assistants.Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    {assistant, config_version}
  end

  defp link_knowledge_base(config_version, attrs) do
    org_id = config_version.organization_id

    {:ok, kb} =
      Assistants.create_knowledge_base(%{
        name: attrs.kb_name,
        organization_id: org_id
      })

    {:ok, kbv} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        organization_id: org_id,
        knowledge_base_version_id: attrs.knowledge_base_version_id,
        llm_service_id: attrs.llm_service_id,
        files: attrs.files,
        status: attrs.kb_status,
        size: attrs.size,
        kaapi_job_id: attrs[:kaapi_job_id]
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: kbv.id,
        organization_id: org_id,
        inserted_at: now,
        updated_at: now
      }
    ])

    {kb, kbv}
  end
end
