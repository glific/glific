defmodule Glific.Filesearch.VectorStoreTest do
  @moduledoc """
  Tests for VectorStores
  """
  alias Glific.Filesearch.Assistant

  alias Glific.{
    Filesearch.VectorStore,
    Repo
  }

  use GlificWeb.ConnCase

  test "create_vector_store/1 with valid data creates a vector_store", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abc",
      name: "temp VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, _vector_store} = VectorStore.create_vector_store(valid_attrs)
  end

  test "create_vector_store/1 with invalid data not create a vector_store", attrs do
    valid_attrs = %{
      name: "temp VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:error, _vector_store} = VectorStore.create_vector_store(valid_attrs)
  end

  test "get_vector_store/1 with valid id returns a vector_store", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abc",
      name: "temp VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    assert {:ok, %VectorStore{}} = VectorStore.get_vector_store(vector_store.id)
  end

  test "list_vector_stores/1 with returns list of VectorStores matching the filters", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abc",
      name: "temp VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, _vector_store} = VectorStore.create_vector_store(valid_attrs)

    valid_attrs = %{
      vector_store_id: "vs_abcd",
      name: "new VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, _vector_store} = VectorStore.create_vector_store(valid_attrs)

    assert vector_stores =
             VectorStore.list_vector_stores(%{filter: %{name: "VectorStore"}})

    assert length(vector_stores) == 2
  end

  test "update_vector_store/1, updates VectorStore", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcd",
      name: "new VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    valid_attrs = %{
      name: "VectorStore 3",
      files: %{
        "file_1234" => %{
          "name" => "1.pdf"
        }
      }
    }

    assert {:ok, vector_store} = VectorStore.update_vector_store(vector_store, valid_attrs)
    assert vector_store.vector_store_id == "vs_abcd"
    assert vector_store.name == "VectorStore 3"
  end

  test "assitants and VectorStore associations", attrs do
    valid_attrs = %{
      vector_store_id: "vs_abcd",
      name: "new VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, vector_store} = VectorStore.create_vector_store(valid_attrs)

    valid_assistant_attrs = %{
      assistant_id: "asst_abc",
      name: "temp assistant",
      model: "gpt-4o",
      temperature: 1,
      organization_id: attrs.organization_id,
      vector_store_id: vector_store.id
    }

    assert {:ok, assistant} = Assistant.create_assistant(valid_assistant_attrs)

    assert %VectorStore{assistants: _assistants} =
             Repo.preload(vector_store, :assistants)

    assert %Assistant{vector_store: _vector_store} =
             Repo.preload(assistant, :vector_store)
  end
end
