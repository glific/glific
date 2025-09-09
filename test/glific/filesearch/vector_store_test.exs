defmodule Glific.Filesearch.VectorStoreTest do
  @moduledoc """
  Tests for VectorStores
  """
  use Glific.DataCase

  alias Glific.Filesearch.Assistant
  alias Glific.Filesearch.VectorStore
  alias Glific.Repo

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

  test "upsert_vector_store/1 creates a vector_store when it doesn't exist", attrs do
    valid_attrs = %{
      vector_store_id: "vs_upsert_new",
      name: "New Upserted VectorStore",
      files: %{},
      size: 129_837,
      status: "completed",
      organization_id: attrs.organization_id
    }

    assert {:ok, vector_store} = VectorStore.upsert_vector_store(valid_attrs)
    assert vector_store.vector_store_id == "vs_upsert_new"
    assert vector_store.name == "New Upserted VectorStore"
  end

  test "upsert_vector_store/1 updates name when vector_store already exists", attrs do
    # First create a vector store
    initial_attrs = %{
      vector_store_id: "vs_upsert_existing",
      name: "Initial VectorStore",
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, initial_vector_store} = VectorStore.create_vector_store(initial_attrs)
    assert initial_vector_store.name == "Initial VectorStore"

    # Now upsert with the same vector_store_id but different name
    updated_attrs = %{
      vector_store_id: "vs_upsert_existing",
      name: "Updated VectorStore",
      status: initial_vector_store.status,
      size: 129_837,
      files: %{},
      organization_id: attrs.organization_id
    }

    assert {:ok, updated_vector_store} = VectorStore.upsert_vector_store(updated_attrs)
    assert updated_vector_store.id == initial_vector_store.id
    assert updated_vector_store.status == initial_vector_store.status
    assert updated_vector_store.vector_store_id == "vs_upsert_existing"
    assert updated_vector_store.name == "Updated VectorStore"
    assert updated_vector_store.size == 129_837
  end

  test "upsert_vector_store/1 with invalid data returns error", attrs do
    invalid_attrs = %{
      name: "Invalid VectorStore",
      files: %{},
      organization_id: attrs.organization_id
      # missing required vector_store_id
    }

    assert {:error, changeset} = VectorStore.upsert_vector_store(invalid_attrs)
    assert %{vector_store_id: ["can't be blank"]} = errors_on(changeset)
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
