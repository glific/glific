defmodule Glific.FilesearchTest do
  @moduledoc """
  Tests for public filesearch APIs
  """

  alias Glific.Filesearch.Assistant

  alias Glific.{
    Assistants,
    Assistants.AssistantConfigVersion,
    Filesearch,
    Filesearch.VectorStore,
    Partners,
    Repo
  }

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Ecto.Query

  load_gql(
    :create_assistant,
    GlificWeb.Schema,
    "assets/gql/filesearch/create_assistant.gql"
  )

  load_gql(
    :delete_assistant,
    GlificWeb.Schema,
    "assets/gql/filesearch/delete_assistant.gql"
  )

  load_gql(
    :update_assistant,
    GlificWeb.Schema,
    "assets/gql/filesearch/update_assistant.gql"
  )

  load_gql(
    :assistant,
    GlificWeb.Schema,
    "assets/gql/filesearch/assistant_by_id.gql"
  )

  load_gql(
    :assistants,
    GlificWeb.Schema,
    "assets/gql/filesearch/list_assistants.gql"
  )

  load_gql(
    :list_models,
    GlificWeb.Schema,
    "assets/gql/filesearch/list_models.gql"
  )

  setup do
    FunWithFlags.disable(:is_kaapi_enabled,
      for_actor: %{organization_id: 1}
    )

    :ok
  end

  test "upload_file/1, uploads the file successfully", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/files"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-XNgygnDzO9cTs3YZLJWRscoq",
            status: "processed",
            filename: "sample.pdf",
            bytes: 54_836,
            object: "file",
            created_at: 1_727_027_487,
            purpose: "assistants",
            status_details: nil
          }
        }
    end)

    assert {:ok, %{file_id: _, filename: _}} =
             Filesearch.upload_file(%{
               media: %Plug.Upload{
                 path:
                   "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
                 content_type: "application/pdf",
                 filename: "sample.pdf"
               },
               organization_id: user.organization_id
             })
  end

  test "upload_file/1, uploads the file failed due to unsupported file", %{user: user} do
    assert {:error, "Files with extension '.csv' not supported in Filesearch"} =
             Filesearch.upload_file(%{
               media: %Plug.Upload{
                 path:
                   "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
                 content_type: "application/csv",
                 filename: "sample.csv"
               },
               organization_id: user.organization_id
             })
  end

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
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{id: "new-kaapi-uuid-upd"}}
        }
    end)

    # updating with empty input variables - no changes, should return current state
    {:ok, query_data} =
      auth_query_gql_by(:update_assistant, attrs.user,
        variables: %{
          "input" => %{},
          "id" => unified_assistant.id
        }
      )

    assert query_data.data["updateAssistant"]["assistant"]["assistant_id"] ==
             unified_assistant.assistant_display_id

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

    assert query_data.data["updateAssistant"]["assistant"]["temperature"] == 1.8

    assert %{"name" => "assistant2"} =
             query_data.data["updateAssistant"]["assistant"]

    assert query_data.data["updateAssistant"]["assistant"]["assistant_id"] ==
             unified_assistant.assistant_display_id
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
        vector_store_id: "vs_test_123",
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
    assert vector_store["vector_store_id"] == "vs_test_123"
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
      kaapi_uuid: "asst_abc2"
    })

    # fetch all
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user, variables: %{})

    assert length(result.data["Assistants"]) == 2

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
        kaapi_uuid: "asst_xyz"
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

  test "import_assistant/2, invalid assistant", attrs do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 404,
          body: %{
            error: %{
              message: "No assistant found with id 'asst_ljpFv60NIlSmXZdnVYHMNu'."
            }
          }
        }
    end)

    {:error, "No assistant found" <> _} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNu", attrs.user.organization_id)
  end

  test "import_assistant/2, assistant not enabled filesearch", attrs do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNu",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            tools: [],
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }
    end)

    {:error, "Please enable filesearch for this assistant"} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNu", attrs.user.organization_id)
  end

  test "import_assistant/2, valid assistant but without vector_store", attrs do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: []}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }
    end)

    {:ok,
     %Assistant{
       vector_store_id: nil,
       name: "test-sync",
       temperature: 1.0,
       assistant_id: "asst_ljpFv60NIlSmXZdnVYHMNuq2"
     }} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)
  end

  test "import_assistant/2, valid assistant and vector_store but vector_store api failure",
       attrs do
    Tesla.Mock.mock(fn
      %{method: :get, url: "https://api.openai.com/v1/assistants/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: ["vs_dg18J5IR6vH19teaRS3QQ7KV"]}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/vector_stores/" <> _} ->
        %Tesla.Env{
          status: 404,
          body: %{
            error: %{
              message: "vector store fetch failed"
            }
          }
        }
    end)

    {:error, "vector store fetch failed"} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNu", attrs.user.organization_id)
  end

  test "import_assistant/2, valid assistant and vector_store but vector_store_files api failure",
       attrs do
    Tesla.Mock.mock(fn
      %{method: :get, url: "https://api.openai.com/v1/assistants/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: ["vs_fxTfuin6XLBEqpIXSykw0bPI"]}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }

      %{
        method: :get,
        url: "https://api.openai.com/v1/vector_stores/vs_fxTfuin6XLBEqpIXSykw0bPI/files"
      } ->
        %Tesla.Env{
          status: 404,
          body: %{
            error: %{
              message: "vector store file fetch failed"
            }
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/vector_stores/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
            name: "Vector store for test-sync",
            status: "completed",
            object: "vector_store",
            created_at: 1_731_062_489,
            usage_bytes: 2188
          }
        }
    end)

    {:error, "vector store file fetch failed"} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)
  end

  test "import_assistant/2, valid assistant and vector_store but files api failure", attrs do
    Tesla.Mock.mock(fn
      %{method: :get, url: "https://api.openai.com/v1/assistants/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: ["vs_fxTfuin6XLBEqpIXSykw0bPI"]}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }

      %{
        method: :get,
        url: "https://api.openai.com/v1/vector_stores/vs_fxTfuin6XLBEqpIXSykw0bPI/files"
      } ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: [
              %{
                id: "file-sNDXUc9cysWhFDBF3ftsDnPB",
                status: "completed",
                last_error: nil,
                object: "vector_store.file",
                vector_store_id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
                created_at: 1_731_062_491,
                usage_bytes: 2188,
                chunking_strategy: %{
                  type: "static",
                  static: %{max_chunk_size_tokens: 800, chunk_overlap_tokens: 400}
                }
              }
            ],
            object: "list"
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/vector_stores/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
            name: "Vector store for test-sync",
            status: "completed",
            object: "vector_store",
            created_at: 1_731_062_489,
            usage_bytes: 2188
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/files/" <> _} ->
        %Tesla.Env{
          status: 404,
          body: %{
            error: %{
              message: "file fetch failed"
            }
          }
        }
    end)

    {:error, "Failed to retrieve file"} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)
  end

  test "import_assistant/2, valid assistant and vector_store", attrs do
    Tesla.Mock.mock(fn
      %{method: :get, url: "https://api.openai.com/v1/assistants/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: ["vs_fxTfuin6XLBEqpIXSykw0bPI"]}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }

      %{
        method: :get,
        url: "https://api.openai.com/v1/vector_stores/vs_fxTfuin6XLBEqpIXSykw0bPI/files"
      } ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: [
              %{
                id: "file-sNDXUc9cysWhFDBF3ftsDnPB",
                status: "completed",
                last_error: nil,
                object: "vector_store.file",
                vector_store_id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
                created_at: 1_731_062_491,
                usage_bytes: 2188,
                chunking_strategy: %{
                  type: "static",
                  static: %{max_chunk_size_tokens: 800, chunk_overlap_tokens: 400}
                }
              }
            ],
            object: "list"
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/vector_stores/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
            name: "Vector store for test-sync",
            status: "completed",
            object: "vector_store",
            created_at: 1_731_062_489,
            usage_bytes: 2188
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/files/file-sNDXUc9cysWhFDBF3ftsDnPB"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-sNDXUc9cysWhFDBF3ftsDnPB",
            filename: "Dev Policies.pdf",
            bytes: 78_063,
            object: "file",
            created_at: 1_731_062_487,
            purpose: "assistants"
          }
        }
    end)

    {:ok, %Assistant{vector_store_id: vs_id}} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)

    assert is_integer(vs_id)
  end

  test "import_assistant/2, trying to import an assistant which exists in Glific", attrs do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-sync",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: []}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }
    end)

    {:ok,
     %Assistant{
       vector_store_id: nil,
       name: "test-sync",
       temperature: 1.0,
       assistant_id: "asst_ljpFv60NIlSmXZdnVYHMNuq2"
     }} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)

    {:error, _} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)
  end

  test "import_assistant/2, when vector_store already exists in the system", attrs do
    # First create a vector store in the system
    existing_vector_store_id = "vs_fxTfuin6XLBEqpIXSykw0bPI"

    {:ok, existing_vector_store} =
      VectorStore.create_vector_store(%{
        vector_store_id: existing_vector_store_id,
        name: "Existing Vector Store",
        files: %{},
        organization_id: attrs.user.organization_id
      })

    Tesla.Mock.mock(fn
      %{method: :get, url: "https://api.openai.com/v1/assistants/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_ljpFv60NIlSmXZdnVYHMNuq2",
            name: "test-with-existing-vs",
            instructions: "",
            description: nil,
            metadata: %{},
            object: "assistant",
            model: "gpt-4o",
            temperature: 1.0,
            tool_resources: %{file_search: %{vector_store_ids: [existing_vector_store_id]}},
            created_at: 1_730_961_252,
            response_format: %{type: "text"},
            top_p: 1.0
          }
        }

      %{
        method: :get,
        url: "https://api.openai.com/v1/vector_stores/vs_fxTfuin6XLBEqpIXSykw0bPI/files"
      } ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: [
              %{
                id: "file-sNDXUc9cysWhFDBF3ftsDnPB",
                status: "completed",
                last_error: nil,
                object: "vector_store.file",
                vector_store_id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
                created_at: 1_731_062_491,
                usage_bytes: 2188,
                chunking_strategy: %{
                  type: "static",
                  static: %{max_chunk_size_tokens: 800, chunk_overlap_tokens: 400}
                }
              }
            ],
            object: "list"
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/vector_stores/" <> _} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_fxTfuin6XLBEqpIXSykw0bPI",
            name: "Updated Vector Store Name",
            status: "completed",
            object: "vector_store",
            created_at: 1_731_062_489,
            usage_bytes: 2188
          }
        }

      %{method: :get, url: "https://api.openai.com/v1/files/file-sNDXUc9cysWhFDBF3ftsDnPB"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-sNDXUc9cysWhFDBF3ftsDnPB",
            filename: "Dev Policies.pdf",
            bytes: 78_063,
            object: "file",
            created_at: 1_731_062_487,
            purpose: "assistants"
          }
        }
    end)

    {:ok, %Assistant{vector_store_id: vs_id}} =
      Filesearch.import_assistant("asst_ljpFv60NIlSmXZdnVYHMNuq2", attrs.user.organization_id)

    # Verify that the vector store is the same one
    assert vs_id == existing_vector_store.id

    # Check that the vector store was updated
    {:ok, updated_vector_store} = VectorStore.get_vector_store(vs_id)
    assert updated_vector_store.name == "Updated Vector Store Name"
    assert updated_vector_store.vector_store_id == existing_vector_store_id

    # Verify that files were updated
    assert map_size(updated_vector_store.files) == 1
    assert Map.has_key?(updated_vector_store.files, "file-sNDXUc9cysWhFDBF3ftsDnPB")
  end

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
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
      vector_store_id: "vs_default_#{:rand.uniform(10000)}",
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
        llm_service_id: attrs.vector_store_id,
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
