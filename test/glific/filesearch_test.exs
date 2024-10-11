defmodule Glific.FilesearchTest do
  @moduledoc """
  Tests for public filesearch APIs
  """

  alias Glific.Filesearch.Assistant

  alias Glific.{
    Filesearch,
    Filesearch.VectorStore,
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
    :add_assistant_files,
    GlificWeb.Schema,
    "assets/gql/filesearch/add_assistant_files.gql"
  )

  load_gql(
    :remove_assistant_file,
    GlificWeb.Schema,
    "assets/gql/filesearch/remove_assistant_file.gql"
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

  test "valid create assistant", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/assistants"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_123"
          }
        }
    end)

    result =
      auth_query_gql_by(:create_assistant, user, variables: %{})

    assert {:ok, query_data} = result
    assert "Assistant" <> _ = query_data.data["createAssistant"]["assistant"]["name"]
  end

  test "create assistant failed due to api failure", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/assistants"} ->
        %Tesla.Env{
          status: 500,
          body: %{}
        }
    end)

    result =
      auth_query_gql_by(:create_assistant, user, variables: %{})

    assert {:ok, query_data} = result
    assert length(query_data.errors) == 1
  end

  test "delete_assistant/1, valid deletion", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "VectorStore 1",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id,
      vector_store_id: vector_store.id
    }

    {:ok, assistant} = Assistant.create_assistant(valid_attrs)

    Tesla.Mock.mock(fn
      %{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{
            deleted: true
          }
        }
    end)

    result =
      auth_query_gql_by(:delete_assistant, attrs.user,
        variables: %{
          "id" => assistant.id
        }
      )

    assert {:ok, query_data} = result
    assert query_data.data["deleteAssistant"]["assistant"]["name"] == "new assistant"

    # deleting assistant should delete attached vector store
    assert {:error, _} = VectorStore.get_vector_store(vector_store.id)
  end

  test "delete_assistant/1, invalid deletion", attrs do
    result =
      auth_query_gql_by(:delete_assistant, attrs.user,
        variables: %{
          "id" => 0
        }
      )

    assert {:ok, query_data} = result
    assert length(query_data.data["deleteAssistant"]["errors"]) == 1
  end

  test "update assistant", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, assistant} = Assistant.create_assistant(valid_attrs)

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_abc"
          }
        }
    end)

    # updating with empty input variables
    {:ok, query_data} =
      auth_query_gql_by(:update_assistant, attrs.user,
        variables: %{
          "input" => %{},
          "id" => assistant.id
        }
      )

    assert query_data.data["updateAssistant"]["assistant"]["assistant_id"] == "asst_abc"

    # # updating with some input variables except vector_store_id
    {:ok, query_data} =
      auth_query_gql_by(:update_assistant, attrs.user,
        variables: %{
          "input" => %{
            "name" => "assistant2",
            "instructions" => "no instruction",
            "temperature" => 1.8
          },
          "id" => assistant.id
        }
      )

    assert {:ok, %{temperature: 1.8}} = Assistant.get_assistant(assistant.id)

    assert %{"name" => "assistant2", "temperature" => 1.8} =
             query_data.data["updateAssistant"]["assistant"]
  end

  test "add_assistant_files and remove assistant file, assistant doesnt has vectorStore", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, assistant} = Assistant.create_assistant(valid_attrs)

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_abc"
          }
        }

      %{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{
            deleted: true
          }
        }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:add_assistant_files, attrs.user,
        variables: %{
          "media_info" => [
            %{
              "file_id" => "file_abc",
              "filename" => "abc"
            },
            %{
              "file_id" => "file_xyz",
              "filename" => "xyz"
            }
          ],
          "id" => assistant.id
        }
      )

    assert %{"name" => "new assistant", "vector_store" => %{"vector_store_id" => "vs_abc"}} =
             query_data.data["add_assistant_files"]["assistant"]

    {:ok, query_data} =
      auth_query_gql_by(:remove_assistant_file, attrs.user,
        variables: %{
          "file_id" => "file_abc",
          "id" => assistant.id
        }
      )

    assert length(query_data.data["RemoveAssistantFile"]["assistant"]["vector_store"]["files"]) ==
             1

    # If deleted: false from openAI

    Tesla.Mock.mock(fn
      %{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{
            deleted: false
          }
        }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:remove_assistant_file, attrs.user,
        variables: %{
          "file_id" => "file_xyz",
          "id" => assistant.id
        }
      )

    assert length(query_data.errors) == 1
  end

  test "add_assistant_files, assistant already has a vectorStore", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, assistant} = Assistant.create_assistant(valid_attrs)

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_abc"
          }
        }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:add_assistant_files, attrs.user,
        variables: %{
          "media_info" => [
            %{
              "file_id" => "file_abc",
              "filename" => "abc"
            },
            %{
              "file_id" => "file_xyz",
              "filename" => "xyz"
            }
          ],
          "id" => assistant.id
        }
      )

    assert %{"name" => "new assistant", "vector_store" => %{"vector_store_id" => "vs_abc"}} =
             query_data.data["add_assistant_files"]["assistant"]

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_abc"
          }
        }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:add_assistant_files, attrs.user,
        variables: %{
          "media_info" => [
            %{
              "file_id" => "file_lmn",
              "filename" => "lmn"
            }
          ],
          "id" => assistant.id
        }
      )

    assert %{"name" => "new assistant", "vector_store" => %{"vector_store_id" => "vs_abc"}} =
             query_data.data["add_assistant_files"]["assistant"]
  end

  test "get assistant", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, assistant} = Assistant.create_assistant(valid_attrs)

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

  test "list assistants", attrs do
    # empty assistants
    {:ok, result} =
      auth_query_gql_by(:assistants, attrs.user, variables: %{})

    assert result.data["Assistants"] == []

    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, _assistant} = Assistant.create_assistant(valid_attrs)

    valid_attrs = %{
      assistant_id: "asst_abc2",
      name: "new assistant 2",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, _assistant} = Assistant.create_assistant(valid_attrs)

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

    valid_attrs = %{
      assistant_id: "asst_xyz",
      name: "new assistant 3",
      temperature: 1,
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    {:ok, _assistant} = Assistant.create_assistant(valid_attrs)

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

    Assistant
    |> where([vs], vs.assistant_id == "asst_xyz")
    |> update([vs], set: [inserted_at: ^date])
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
end
