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
    :create_vector_store,
    GlificWeb.Schema,
    "assets/gql/filesearch/create_vector_store.gql"
  )

  load_gql(
    :delete_vector_store,
    GlificWeb.Schema,
    "assets/gql/filesearch/delete_vector_store.gql"
  )

  load_gql(
    :remove_vector_store_file,
    GlificWeb.Schema,
    "assets/gql/filesearch/remove_vector_store_file.gql"
  )

  load_gql(
    :vector_stores,
    GlificWeb.Schema,
    "assets/gql/filesearch/list_vector_stores.gql"
  )

  load_gql(
    :vector_store,
    GlificWeb.Schema,
    "assets/gql/filesearch/get_vector_store.gql"
  )

  load_gql(
    :update_vector_store,
    GlificWeb.Schema,
    "assets/gql/filesearch/update_vector_store.gql"
  )

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

  test "valid create vector_store", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/vector_stores"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_123"
          }
        }
    end)

    result =
      auth_query_gql_by(:create_vector_store, user, variables: %{})

    assert {:ok, query_data} = result
    assert "vectorStore" <> _ = query_data.data["createVectorStore"]["vectorStore"]["name"]
  end

  test "create vector_store failed due to api failure", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/vector_stores"} ->
        %Tesla.Env{
          status: 500,
          body: %{}
        }
    end)

    result =
      auth_query_gql_by(:create_vector_store, user, variables: %{})

    assert {:ok, query_data} = result
    assert length(query_data.errors) == 1
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

  describe "Add files to VectorStore" do
    setup attrs do
      valid_attrs = %{
        vector_store_id: "vs_abcd",
        name: "new VectorStore",
        files: %{},
        organization_id: attrs.organization_id
      }

      {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)
      Map.merge(attrs, %{vector_store: vector_store})
    end

    test "Add openAI files to vector_store", attrs do
      media_files = [
        %Plug.Upload{
          path:
            "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
          content_type: "application/pdf",
          filename: "sample.pdf"
        },
        %Plug.Upload{
          path:
            "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gk/T/plug-1727-NXFz/multipart-1727169241-575672640710-2",
          content_type: "application/pdf",
          filename: "sample_2.pdf"
        }
      ]

      params = %{
        id: attrs.vector_store.id,
        media: media_files,
        organization_id: attrs.organization_id
      }

      Tesla.Mock.mock_global(fn
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

        %{method: :post, url: "https://api.openai.com/v1/vector_stores" <> _} ->
          %Tesla.Env{
            status: 200,
            body: %{
              id: "file-XNgygnDzO9cTs3YZLJWRscoq",
              object: "vector_store.file",
              created_at: 1_699_061_776,
              usage_bytes: 1234,
              vector_store_id: attrs.vector_store.vector_store_id,
              status: "completed",
              last_error: nil
            }
          }
      end)

      {:ok, %VectorStore{files: files}} =
        Filesearch.add_vector_store_files(params)

      assert Map.keys(files) |> length() == 1
    end

    test "Add openAI files to vector_store, handling API failures", attrs do
      media_files = [
        %Plug.Upload{
          path:
            "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
          content_type: "application/pdf",
          filename: "sample.pdf"
        }
      ]

      params = %{
        id: attrs.vector_store.id,
        media: media_files,
        organization_id: attrs.organization_id
      }

      Tesla.Mock.mock_global(fn
        %{method: :post, url: "https://api.openai.com/v1/files"} ->
          %Tesla.Env{
            status: 400,
            body: %{
              error: %{
                message: "Upload failed"
              }
            }
          }

        %{method: :post, url: "https://api.openai.com/v1/vector_stores" <> _} ->
          %Tesla.Env{
            status: 200,
            body: %{
              error: %{
                message: "attach VectorStore failed"
              }
            }
          }
      end)

      {:ok, %VectorStore{files: files}} = Filesearch.add_vector_store_files(params)
      assert Map.keys(files) |> length() == 0
    end

    test "Add openAI files to vector_store, handling API failures 2", attrs do
      media_files = [
        %Plug.Upload{
          path:
            "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
          content_type: "application/pdf",
          filename: "sample.pdf"
        }
      ]

      params = %{
        id: attrs.vector_store.id,
        media: media_files,
        organization_id: attrs.organization_id
      }

      Tesla.Mock.mock_global(fn
        %{method: :post, url: "https://api.openai.com/v1/files"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              id: "file-XNgygnDzO9cTs3YZLJWRscoq",
              object: "vector_store.file",
              created_at: 1_699_061_776,
              usage_bytes: 1234,
              vector_store_id: attrs.vector_store.vector_store_id,
              status: "completed",
              last_error: nil
            }
          }

        %{method: :post, url: "https://api.openai.com/v1/vector_stores" <> _} ->
          %Tesla.Env{
            status: 400,
            body: %{
              error: %{
                message: "attach VectorStore failed"
              }
            }
          }
      end)

      {:ok, %VectorStore{files: files}} = Filesearch.add_vector_store_files(params)
      assert Map.keys(files) |> length() == 0
    end
  end

  test "delete_vector_store/1, valid deletion", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcde",
      name: "new VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

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
      auth_query_gql_by(:delete_vector_store, attrs.user,
        variables: %{
          "id" => vector_store.id
        }
      )

    assert {:ok, query_data} = result
    assert query_data.data["deleteVectorStore"]["vectorStore"]["name"] == "new VectorStore"
  end

  test "delete_vector_store/1, invalid deletion", attrs do
    result =
      auth_query_gql_by(:delete_vector_store, attrs.user,
        variables: %{
          "id" => 0
        }
      )

    assert {:ok, query_data} = result
    assert length(query_data.data["deleteVectorStore"]["errors"]) == 1
  end

  test "remove VectorStore file, valid removal", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcde",
      name: "new VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    VectorStore.update_vector_store(vector_store, %{
      files: %{
        "file-Cbfk7rPQG6geG8nfUCcn4zJm" => %{
          id: "file-Cbfk7rPQG6geG8nfUCcn4zJm",
          size: 54_836,
          status: "in_progress",
          filename: "sample.pdf"
        },
        "file-Cbfk7rPQG6geG8nfUCcn4zabc" => %{
          id: "file-Cbfk7rPQG6geG8nfUCcn4zabc",
          size: 54_836,
          status: "in_progress",
          filename: "sample2.pdf"
        }
      }
    })

    Tesla.Mock.mock(fn
      %{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-Cbfk7rPQG6geG8nfUCcn4zJm",
            object: "vector_store.file.deleted",
            deleted: true
          }
        }
    end)

    {:ok, result} =
      auth_query_gql_by(:remove_vector_store_file, attrs.user,
        variables: %{
          "id" => vector_store.id,
          "file_id" => "file-Cbfk7rPQG6geG8nfUCcn4zJm"
        }
      )

    assert length(result.data["RemoveVectorStoreFile"]["vectorStore"]["files"]) == 1
  end

  test "remove VectorStore file, invalid fileId", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "new VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    VectorStore.update_vector_store(vector_store, %{
      files: %{
        "file-Cbfk7rPQG6geG8nfUCcn4zJm" => %{
          id: "file-Cbfk7rPQG6geG8nfUCcn4zJm",
          size: 54_836,
          status: "in_progress",
          filename: "sample.pdf"
        }
      }
    })

    Tesla.Mock.mock(fn
      %{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-Cbfk7rPQG6geG8nfUCcn4zJm",
            object: "vector_store.file.deleted",
            deleted: true
          }
        }
    end)

    {:ok, result} =
      auth_query_gql_by(:remove_vector_store_file, attrs.user,
        variables: %{
          "id" => vector_store.id,
          "file_id" => "file-Cbfk7rPQG6geG8"
        }
      )

    assert "Removing VectorStore failed" <> _ = List.first(result.errors) |> Map.get(:message)
  end

  test "list vector_stores", attrs do
    # empty vectorstores
    {:ok, result} =
      auth_query_gql_by(:vector_stores, attrs.user, variables: %{})

    assert result.data["VectorStores"] == []

    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "VectorStore 1",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, _vector_store} = VectorStore.create_vector_store(valid_attrs)

    valid_attrs = %{
      vector_store_id: "vs_xyz",
      name: "VectorStore 2",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, _vector_store} = VectorStore.create_vector_store(valid_attrs)

    # fetch all
    {:ok, result} =
      auth_query_gql_by(:vector_stores, attrs.user, variables: %{})

    assert length(result.data["VectorStores"]) == 2

    # limit 1
    {:ok, result} =
      auth_query_gql_by(:vector_stores, attrs.user,
        variables: %{
          "opts" => %{
            "limit" => 1
          }
        }
      )

    assert length(result.data["VectorStores"]) == 1

    valid_attrs = %{
      vector_store_id: "vs_xyzw",
      name: "VectorStore 3",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, _vector_store} = VectorStore.create_vector_store(valid_attrs)

    # limit 1, offset 2
    {:ok, result} =
      auth_query_gql_by(:vector_stores, attrs.user,
        variables: %{
          "opts" => %{
            "limit" => 1,
            "offset" => 2
          }
        }
      )

    date = DateTime.utc_now() |> DateTime.add(-2 * 86_400)

    VectorStore
    |> where([vs], vs.vector_store_id == "vs_xyzw")
    |> update([vs], set: [inserted_at: ^date])
    |> Repo.update_all([])

    assert length(result.data["VectorStores"]) == 1

    # limit 1, default asc by inserted_at
    {:ok, result} =
      auth_query_gql_by(:vector_stores, attrs.user,
        variables: %{
          "opts" => %{
            "limit" => 1
          }
        }
      )

    assert %{"name" => "VectorStore 3"} = List.first(result.data["VectorStores"])

    # search by name
    {:ok, result} =
      auth_query_gql_by(:vector_stores, attrs.user,
        variables: %{
          "filter" => %{
            "name" => "3"
          }
        }
      )

    assert %{"name" => "VectorStore 3"} = List.first(result.data["VectorStores"])
  end

  test "fetch a VectorStore", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "VectorStore 1",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    {:ok, result} =
      auth_query_gql_by(:vector_store, attrs.user,
        variables: %{
          "id" => vector_store.id
        }
      )

    assert result.data["vector_store"]["vectorStore"]["vector_store_id"] == "vs_abcdef"

    {:ok, result} =
      auth_query_gql_by(:vector_store, attrs.user,
        variables: %{
          "id" => 0
        }
      )

    assert List.first(result.data["vector_store"]["errors"])["message"] == "Resource not found"
  end

  test "update VectorStore", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "VectorStore 1",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-Cbfk7rPQG6geG8nfUCcn4zJm"
          }
        }
    end)

    {:ok, result} =
      auth_query_gql_by(:update_vector_store, attrs.user,
        variables: %{
          "input" => %{
            "name" => "new VectorStore"
          },
          "id" => vector_store.id
        }
      )

    assert result.data["UpdateVectorStore"]["vectorStore"]["name"] == "new VectorStore"
  end

  @tag :asst
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

  @tag :asst
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

  @tag :asst_1
  test "valid create assistant with vector_store", attrs do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/assistants"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "asst_123"
          }
        }
    end)

    # invalid vector_store_id
    result =
      auth_query_gql_by(:create_assistant, attrs.user,
        variables: %{
          "input" => %{
            "vector_store_id" => 3
          }
        }
      )

    assert {:ok, query_data} = result

    assert "Vector_store_id: does not exist" =
             List.first(query_data.data["createAssistant"]["errors"])["message"]

    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "VectorStore 1",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    # valid vector_store_id
    result =
      auth_query_gql_by(:create_assistant, attrs.user,
        variables: %{
          "input" => %{
            "vector_store_id" => vector_store.id
          }
        }
      )

    assert {:ok, query_data} = result

    assert "Assistant" <> _ =
             query_data.data["createAssistant"]["assistant"]["name"]
  end

  @tag :asst_1
  test "delete_assistant/1, valid deletion", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "new assistant",
      settings: %{},
      model: "gpt-4o",
      organization_id: attrs.organization_id
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
  end

  @tag :asst_1
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
end
