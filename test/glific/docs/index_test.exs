defmodule Glific.Docs.IndexTest do
  @moduledoc "Storing and reading the embedding artifact."

  use ExUnit.Case, async: false

  alias Glific.Docs.{Chunk, Index, Search}

  setup_all do
    Index.warm()
    :ok
  end

  describe "the shipped artifact" do
    test "it holds the whole corpus" do
      assert Index.count() > 100
      assert length(Index.chunks()) == Index.count()
    end

    test "it records the model and width it was built with" do
      metadata = Index.metadata()

      assert is_binary(metadata.model)
      assert is_integer(metadata.dimensions)
    end

    test "every vector is the recorded width" do
      # A vector of another width came from another model, and scoring it
      # against this one ranks at random.
      expected = Index.metadata().dimensions * 4

      for entry <- Index.entries(), entry.vector do
        assert byte_size(entry.vector) == expected
      end
    end

    test "the path names the documentation directory" do
      assert Index.artifact_path() =~ "docs_kb"
    end
  end

  describe "with no artifact built" do
    setup do
      # `_build/.../priv` is a symlink to `priv`, so both names are one file.
      paths = [
        Index.artifact_path(),
        Path.join([File.cwd!(), "priv", "docs_kb", "embeddings.etf"])
      ]

      original = paths |> Enum.find(&File.exists?/1) |> File.read!()

      on_exit(fn ->
        Enum.each(paths, &File.write!(&1, original))
        Index.warm()
      end)

      Enum.each(paths, &File.rm/1)
      :persistent_term.erase({Index, :entries})
      :persistent_term.erase({Index, :metadata})
      :ok
    end

    test "the documents are still chunked, so the lexical leg keeps working" do
      Index.warm()

      assert Index.count() > 100
      assert Enum.all?(Index.entries(), &is_nil(&1.vector))
    end

    test "a lexical search still returns answers" do
      Index.warm()

      assert Search.find("how do I publish a flow", limit: 5) != []
    end

    test "the semantic leg stays silent rather than scoring empty vectors" do
      Index.warm()

      assert Search.semantic_leg("anything", Index.entries(), Index.pack([1.0, 0.0])) ==
               []
    end

    test "metadata is empty rather than raising" do
      assert Index.metadata() == %{}
    end
  end

  describe "packing" do
    test "a packed vector is four bytes per dimension" do
      assert byte_size(Index.pack([1.0, 2.0, 3.0])) == 12
    end

    test "packing normalises, so a vector matches itself exactly" do
      vector = Index.pack([3.0, 4.0])
      assert_in_delta Index.similarity(vector, vector), 1.0, 0.0001
    end

    test "scale is removed, so only direction is compared" do
      assert_in_delta Index.similarity(Index.pack([1.0, 1.0]), Index.pack([5.0, 5.0])),
                      1.0,
                      0.0001
    end

    test "opposite directions score minus one" do
      assert_in_delta Index.similarity(Index.pack([1.0, 0.0]), Index.pack([-1.0, 0.0])),
                      -1.0,
                      0.0001
    end

    test "a zero vector does not divide by zero" do
      assert byte_size(Index.pack([0.0, 0.0])) == 8
    end
  end

  describe "writing" do
    @tag :tmp_dir
    test "what is written can be read back", %{tmp_dir: _tmp_dir} do
      entry = %{chunk: chunk(), vector: Index.pack([1.0, 0.0])}

      assert :ok = Index.write!([entry], model: "test:model", dimensions: 2)
      assert Index.metadata().model == "test:model"
    after
      # Leave the shipped artifact as the suite found it.
      System.cmd("git", ["checkout", "--", "priv/docs_kb/embeddings.etf"], stderr_to_stdout: true)
      Index.warm()
    end
  end

  defp chunk do
    %Chunk{doc_file: "doc", heading_path: "Title", body: "body", content_hash: "hash"}
  end
end
