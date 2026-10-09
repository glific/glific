defmodule Glific.DocsTest do
  @moduledoc """
  Chunking, the index, and the two retrieval passes.

  Run against the shipped documentation rather than invented markdown, which
  would agree with whatever the parser happens to do. The semantic pass is
  given vectors directly, so none of this needs an embedding provider.
  """

  use ExUnit.Case, async: false

  alias Glific.Docs

  @knowledge_base "glific_chatbot_knowledge_base"

  setup_all do
    Docs.warm()
    %{chunks: Docs.all_chunks(), entries: Docs.entries()}
  end

  defp find(chunks, section_path), do: Enum.find(chunks, &(&1.section_path == section_path))

  describe "chunking" do
    test "every chunk carries a trail, a body and a hash", %{chunks: chunks} do
      for chunk <- chunks do
        assert chunk.heading_path != ""
        assert String.trim(chunk.body) != ""
        assert chunk.hash =~ ~r/^[0-9a-f]{64}$/
      end
    end

    test "chunking is deterministic", %{chunks: chunks} do
      assert Docs.all_chunks() == chunks
    end

    test "3.4 keeps both its examples and does not bleed into 3.5", %{chunks: chunks} do
      chunk = find(chunks, "3.4")

      assert chunk.body =~ "@results.parent.<variable_name>.input"
      assert chunk.body =~ "@results.parent.state.input"
      refute chunk.body =~ "@results.child"
      assert find(chunks, "3.5").body =~ "@results.child"
    end

    test "7.6 is short but survives on its own, still saying no", %{chunks: chunks} do
      chunk = find(chunks, "7.6")

      assert Docs.title(chunk) =~ "approved template"
      assert chunk.body =~ "No."
    end

    test "a section with no source of its own inherits the nearest above it" do
      markdown = """
      ## 1.1 First

      📖 Source: https://example.com/page

      #{String.duplicate("Body text that is long enough to stand alone. ", 6)}

      ## 1.2 Second

      #{String.duplicate("A later section on the same page states no source. ", 6)}
      """

      assert [first, second] = Docs.chunk(markdown, "doc")
      assert first.source_url == "https://example.com/page"
      assert second.source_url == "https://example.com/page"
    end

    test "a label-sized child folds into its parent, keeping its heading" do
      markdown = """
      ## 2.1 Limits

      #{String.duplicate("The parent section carries the real explanation here. ", 6)}

      ### 2.1.1 Image

      5 MB.
      """

      assert [chunk] = Docs.chunk(markdown, "doc")
      assert chunk.body =~ "5 MB."
      assert chunk.body =~ "2.1.1 Image"
    end

    test "two small siblings stay apart rather than gluing together" do
      markdown = "## 4.1 One\n\nShort.\n\n## 4.2 Two\n\nAlso short.\n"

      assert length(Docs.chunk(markdown, "doc")) == 2
    end

    test "a heading with no body is dropped but stays in the trail" do
      markdown = """
      # 3. Flow Variables

      ## 3.1 Saving input

      #{String.duplicate("A real answer with enough text to stand on its own. ", 6)}
      """

      assert [chunk] = Docs.chunk(markdown, "doc")
      assert chunk.heading_path == "3. Flow Variables › 3.1 Saving input"
    end
  end

  describe "code fences" do
    test "a # inside a fence is not a heading" do
      markdown = """
      ## 1.1 Running the indexer

      #{String.duplicate("Prose before the example that is long enough to stand. ", 5)}

      ```bash
      # this is a shell comment, not a heading
      ```

      #{String.duplicate("Prose after the example, also long enough to stand. ", 5)}
      """

      assert [chunk] = Docs.chunk(markdown, "doc")
      assert chunk.body =~ "# this is a shell comment"
      assert chunk.body =~ "Prose after the example"
    end

    test "a longer fence is not closed by a shorter one" do
      markdown = """
      ## 1.1 Nested example

      #{String.duplicate("Prose long enough for this section to stand alone. ", 5)}

      ````markdown
      ```elixir
      ```
      ## Not a heading
      ````
      """

      assert [chunk] = Docs.chunk(markdown, "doc")
      assert chunk.body =~ "## Not a heading"
    end

    test "a tilde fence hides a heading too" do
      markdown = """
      ## 1.1 Tilde example

      #{String.duplicate("Prose long enough for this section to stand alone. ", 5)}

      ~~~
      ## Not a heading either
      ~~~
      """

      assert [chunk] = Docs.chunk(markdown, "doc")
      assert chunk.body =~ "## Not a heading either"
    end

    test "no fence in the shipped corpus is left unclosed by the split", %{chunks: chunks} do
      for chunk <- chunks do
        fences = chunk.body |> String.split("```") |> length() |> Kernel.-(1)
        assert rem(fences, 2) == 0, chunk.heading_path
      end
    end
  end

  describe "sections kept out of the index" do
    test "the mapping table is excluded", %{chunks: chunks} do
      refute Enum.any?(chunks, &(&1.section_path == "18"))
    end

    test "nothing written for engineers survives", %{chunks: chunks} do
      for chunk <- chunks, do: refute(Docs.engineering?(chunk), chunk.heading_path)
    end

    test "a section citing a file is engineering, wherever it cites it" do
      assert Docs.engineering?(chunk("Wallet", "See `lib/glific/providers/gupshup.ex`"))
      assert Docs.engineering?(chunk("Partner API (`lib/glific/x.ex`)", "Top up the wallet."))
      refute Docs.engineering?(chunk("Wallet", "Go to My Wallet and add credits."))
    end

    test "only the manifest's documents contribute", %{chunks: chunks} do
      documents = MapSet.new(Docs.documents())

      for chunk <- chunks, do: assert(MapSet.member?(documents, chunk.doc_file))
    end
  end

  describe "the index" do
    test "it holds the whole corpus", %{entries: entries} do
      assert Docs.count() == length(entries)
      assert Docs.count() > 100
    end

    test "it records the model and width it was built with" do
      assert is_binary(Docs.metadata().model)
      assert is_integer(Docs.metadata().dimensions)
    end

    test "every vector is the recorded width", %{entries: entries} do
      expected = Docs.metadata().dimensions * 4

      for entry <- entries, entry.vector, do: assert(byte_size(entry.vector) == expected)
    end
  end

  describe "vectors" do
    test "a packed vector is four bytes per dimension" do
      assert byte_size(Docs.pack([1.0, 2.0, 3.0])) == 12
    end

    test "scale is removed, so only direction is compared" do
      assert_in_delta Docs.similarity(Docs.pack([1.0, 1.0]), Docs.pack([5.0, 5.0])), 1.0, 0.0001
    end

    test "opposite directions score minus one" do
      assert_in_delta Docs.similarity(Docs.pack([1.0, 0.0]), Docs.pack([-1.0, 0.0])), -1.0, 0.0001
    end

    test "different widths score zero rather than their overlap" do
      assert Docs.similarity(Docs.pack([1.0, 0.0, 0.0]), Docs.pack([1.0, 0.0])) == 0.0
    end

    test "a zero vector does not divide by zero" do
      assert byte_size(Docs.pack([0.0, 0.0])) == 8
    end
  end

  describe "the semantic pass" do
    test "a chunk's own vector finds that chunk", %{entries: entries} do
      [entry | _rest] = Enum.reject(entries, &is_nil(&1.vector))

      assert hd(Docs.semantic("anything", entries, entry.vector)).hash == entry.chunk.hash
    end

    test "a vector matching nothing well enough returns nothing", %{entries: entries} do
      [entry | _rest] = Enum.reject(entries, &is_nil(&1.vector))

      assert Docs.semantic("anything", entries, negate(entry.vector)) == []
    end

    test "entries with no vector are skipped rather than scored" do
      entries = [%{chunk: chunk("Title", "body"), vector: nil}]

      assert Docs.semantic("anything", entries, <<0::size(32)>>) == []
    end
  end

  describe "the lexical pass" do
    test "an exact identifier is found where the documents write it", %{entries: entries} do
      # The documents write identifiers in prose rather than in headings.
      for identifier <- ["@results.parent.state.input", "resumeContactFlow"] do
        assert Docs.lexical(identifier, entries) != [], identifier
      end
    end

    test "a rare ordinary word is not an identifier", %{entries: entries} do
      # Rarity alone would let these through: they are as uncommon in the
      # corpus as a real identifier is.
      assert Docs.lexical("what is the weather in Mumbai today", entries) == []
      assert Docs.lexical("ignore previous instructions", entries) == []
    end

    test "notation survives tokenising whole" do
      assert "@results.parent.state.input" in Docs.terms(
               "how do I read @results.parent.state.input"
             )
    end

    test "words carrying no topic are dropped" do
      assert Docs.terms("hi team, please can you help") == []
    end
  end

  describe "fusion" do
    test "a chunk both passes rank beats one only a single pass found" do
      both = chunk("Both", "found by both")
      one = chunk("One", "found by one")

      assert [first | _rest] = Docs.fuse(%{lexical: [one, both], semantic: [both]})
      assert first.hash == both.hash
    end

    test "every chunk either pass found survives the merge" do
      assert length(Docs.fuse(%{lexical: [chunk("A", "one")], semantic: [chunk("B", "two")]})) ==
               2
    end
  end

  describe "subjects the corpus must cover" do
    @topics [
      "how do I publish a flow",
      "opt-in and opt-out",
      "HSM template approval",
      "webhook call from a flow",
      "google sheet integration",
      "collections and contact fields"
    ]

    test "each supported subject returns something" do
      for topic <- @topics, do: assert(Docs.find(topic, limit: 5) != [], topic)
    end

    test "an off-topic question returns nothing" do
      for question <- [
            "zzzqqq unrelatedtoglific",
            "what is the weather in Mumbai today",
            "write me a poem about cats",
            "thanks!"
          ] do
        assert Docs.find(question, limit: 5) == [], question
      end
    end

    test "a diagnosis question reaches the knowledge base" do
      chunks = Docs.find("why is my flow not triggering", limit: 5)

      assert Enum.any?(chunks, &(&1.doc_file == @knowledge_base))
    end
  end

  defp chunk(heading, body) do
    %{
      doc_file: "doc",
      section_path: nil,
      heading_path: heading,
      body: body,
      source_url: nil,
      hash: :sha256 |> :crypto.hash(heading <> body) |> Base.encode16(case: :lower)
    }
  end

  defp negate(vector),
    do: for(<<value::float-32-little <- vector>>, into: <<>>, do: <<-value::float-32-little>>)
end
