defmodule Glific.Docs.IndexerTest do
  @moduledoc """
  What goes into the index and what is kept out.

  Building the artifact needs an embedding provider, so what is covered here
  is the selection: which documents are read, and which of their sections are
  excluded before anything is embedded.
  """

  use ExUnit.Case, async: false

  alias Glific.Docs.{Chunk, Index, Indexer}

  describe "the corpus" do
    test "every named document contributes chunks" do
      by_document = Enum.group_by(Indexer.all_chunks(), & &1.doc_file)

      for document <- Indexer.documents() do
        assert Map.has_key?(by_document, document), document
      end
    end

    test "no document outside the manifest leaks in" do
      documents = MapSet.new(Indexer.documents())

      for chunk <- Indexer.all_chunks() do
        assert MapSet.member?(documents, chunk.doc_file), chunk.doc_file
      end
    end

    test "every chunk has a body and a hash" do
      for chunk <- Indexer.all_chunks() do
        assert String.trim(chunk.body) != ""
        assert chunk.content_hash =~ ~r/^[0-9a-f]{64}$/
      end
    end
  end

  describe "sections kept out" do
    test "the mapping table is excluded" do
      # It pairs user phrasings with section numbers, so it matches almost any
      # question and then answers with a pointer instead of an answer.
      refute Enum.any?(Indexer.all_chunks(), &(&1.section_path == "18"))
    end

    test "nothing written for engineers survives" do
      for chunk <- Indexer.all_chunks() do
        refute Indexer.engineering?(chunk), chunk.heading_path
      end
    end

    test "a section citing a file is engineering, wherever it cites it" do
      assert Indexer.engineering?(chunk("Wallet", "See `lib/glific/providers/gupshup.ex`"))
      assert Indexer.engineering?(chunk("Partner API (`lib/glific/x.ex`)", "Top up the wallet."))
      refute Indexer.engineering?(chunk("Wallet", "Go to My Wallet and add credits."))
    end
  end

  describe "building the artifact" do
    setup do
      original = File.read!(Index.artifact_path())
      source = Path.join([File.cwd!(), "priv", "docs_kb", "embeddings.etf"])

      on_exit(fn ->
        File.write!(source, original)
        Application.delete_env(:glific, :docs_embedding_request_options)
        Index.warm()
      end)

      %{original: original}
    end

    # The provider is stubbed, so these do not embed anything for real.
    defp serve_embeddings(dimensions) do
      Application.put_env(:glific, :docs_embedding_request_options,
        req_http_options: [
          plug: fn conn ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            inputs = body |> Jason.decode!() |> Map.fetch!("input") |> List.wrap()

            data =
              Enum.with_index(inputs, fn _input, index ->
                %{"embedding" => List.duplicate(0.1, dimensions), "index" => index}
              end)

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => data, "model" => "stub"}))
          end
        ]
      )
    end

    test "a build embeds every chunk and records what it used" do
      serve_embeddings(8)

      assert {:ok, summary} =
               Indexer.build(force: true, dimensions: 8, model: "openai:text-embedding-3-small")

      assert summary.total == length(Indexer.all_chunks())
      assert summary.embedded == summary.total
      assert summary.reused == 0
      assert summary.dimensions == 8
    end

    test "a second build reuses every vector rather than paying again" do
      serve_embeddings(8)

      {:ok, _first} =
        Indexer.build(force: true, dimensions: 8, model: "openai:text-embedding-3-small")

      assert {:ok, second} = Indexer.build(dimensions: 8, model: "openai:text-embedding-3-small")
      assert second.embedded == 0
      assert second.reused == second.total
    end

    test "changing the width re-embeds, since the spaces are not comparable" do
      serve_embeddings(8)

      {:ok, _first} =
        Indexer.build(force: true, dimensions: 8, model: "openai:text-embedding-3-small")

      serve_embeddings(16)
      assert {:ok, second} = Indexer.build(dimensions: 16, model: "openai:text-embedding-3-small")
      assert second.reused == 0
      assert second.embedded == second.total
    end

    test "a provider failure leaves the previous artifact alone", %{original: original} do
      Application.put_env(:glific, :docs_embedding_request_options,
        req_http_options: [plug: fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end]
      )

      assert {:error, _reason} =
               Indexer.build(force: true, model: "openai:text-embedding-3-small")

      assert File.read!(Index.artifact_path()) == original
    end
  end

  describe "settings" do
    test "the width is a positive number of dimensions" do
      assert Indexer.dimensions() > 0
    end

    test "the model names a provider" do
      assert Indexer.model() =~ ":"
    end
  end

  defp chunk(heading, body) do
    %Chunk{doc_file: "doc", heading_path: heading, body: body, content_hash: "hash"}
  end
end
