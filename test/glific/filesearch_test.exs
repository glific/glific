defmodule Glific.FilesearchTest do
  @moduledoc """
  Tests for public filesearch APIs
  """

  alias Glific.Filesearch.VectorStore
  alias Glific.Filesearch
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

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

  @tag :vs_api
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

  @tag :vs_api
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

  @tag :fileup
  test "upload_file/1, uploads the file successfully", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/files"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "file-XNgygnDzO9cTs3YZLJWRscoq",
            status: "processed",
            filename: "sample.pdf",
            bytes: 54836,
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

  describe "Add files to vector store" do
    setup attrs do
      valid_attrs = %{
        vector_store_id: "vs_abcd",
        name: "new vector store",
        files: %{},
        organization_id: attrs.organization_id
      }

      {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)
      Map.merge(attrs, %{vector_store: vector_store})
    end

    @tag :update_vs_files
    test "Add openAI files to vector_store, passing empty list to add", attrs do
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
              bytes: 54836,
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

      {:ok, %VectorStore{}} = Filesearch.add_vector_store_files(params)
    end
  end

  @tag :del_vs
  test "delete_vector_store/1, valid deletion", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcde",
      name: "new vector store",
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
    assert query_data.data["deleteVectorStore"]["vectorStore"]["name"] == "new vector store"
  end

  @tag :del_vs
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

  @tag :remove_vs_file
  test "remove vector store file, valid removal", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcde",
      name: "new vector store",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    VectorStore.update_vector_store(vector_store, %{
      files: %{
        "file-Cbfk7rPQG6geG8nfUCcn4zJm" => %{
          id: "file-Cbfk7rPQG6geG8nfUCcn4zJm",
          size: 54836,
          status: "in_progress",
          filename: "sample.pdf"
        },
        "file-Cbfk7rPQG6geG8nfUCcn4zabc" => %{
          id: "file-Cbfk7rPQG6geG8nfUCcn4zabc",
          size: 54836,
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

  @tag :remove_vs_file
  test "remove vector store file, invalid fileId", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcdef",
      name: "new vector store",
      files: %{},
      organization_id: attrs.organization_id
    }

    {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    VectorStore.update_vector_store(vector_store, %{
      files: %{
        "file-Cbfk7rPQG6geG8nfUCcn4zJm" => %{
          id: "file-Cbfk7rPQG6geG8nfUCcn4zJm",
          size: 54836,
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

    assert "Removing vector store failed" <> _ = List.first(result.errors) |> Map.get(:message)
  end


end
