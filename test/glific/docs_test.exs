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
    %{sections: Docs.sections(), entries: Docs.entries()}
  end

  describe "the entries" do
    test "every entry has a heading, a body and a hash", %{sections: sections} do
      assert length(sections) > 100

      for section <- sections do
        assert section.heading_path != ""
        assert String.trim(section.body) != ""
        assert section.hash =~ ~r/^[0-9a-f]{64}$/
      end
    end

    test "loading is deterministic", %{sections: sections} do
      assert Docs.sections() == sections
    end

    test "an entry is its front matter and then its prose" do
      document = """
      --- entry
      section: 3.4
      heading: 3. Variables › 3.4 Reading a parent variable
      source: https://example.com/page
      ---

      Use `@results.parent.<name>.input`.
      """

      assert [section] = Docs.parse(document, "a_document")
      assert section.doc_file == "a_document"
      assert section.section_path == "3.4"
      assert section.heading_path == "3. Variables › 3.4 Reading a parent variable"
      assert section.source_url == "https://example.com/page"
      assert section.body == "Use `@results.parent.<name>.input`."
    end

    test "a document holds many entries" do
      document = """
      --- entry
      heading: First
      ---

      One.

      --- entry
      heading: Second
      ---

      Two.
      """

      assert [first, second] = Docs.parse(document, "doc")
      assert first.body == "One."
      assert second.body == "Two."
    end

    test "a heading may contain the colons and separators the documents use" do
      document = "--- entry\nheading: 7.6 Can I edit it: really?\n---\n\nNo.\n"

      assert [section] = Docs.parse(document, "doc")
      assert section.heading_path == "7.6 Can I edit it: really?"
    end

    test "an entry with no heading or no prose is skipped" do
      assert Docs.parse("no entries here", "doc") == []
      assert Docs.parse("--- entry\nheading: Empty\n---\n\n", "doc") == []
    end

    test "every entry belongs to a named document", %{sections: sections} do
      documents = MapSet.new(Docs.documents())

      for section <- sections, do: assert(MapSet.member?(documents, section.doc_file))
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
    test "a section's own vector finds that section", %{entries: entries} do
      [entry | _rest] = Enum.reject(entries, &is_nil(&1.vector))

      assert hd(Docs.semantic("anything", entries, entry.vector)).hash == entry.section.hash
    end

    test "a vector matching nothing well enough returns nothing", %{entries: entries} do
      [entry | _rest] = Enum.reject(entries, &is_nil(&1.vector))

      assert Docs.semantic("anything", entries, negate(entry.vector)) == []
    end

    test "entries with no vector are skipped rather than scored" do
      entries = [%{section: section("Title", "body"), vector: nil}]

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
    test "a section both passes rank beats one only a single pass found" do
      both = section("Both", "found by both")
      one = section("One", "found by one")

      assert [first | _rest] = Docs.fuse(%{lexical: [one, both], semantic: [both]})
      assert first.hash == both.hash
    end

    test "every section either pass found survives the merge" do
      assert length(Docs.fuse(%{lexical: [section("A", "one")], semantic: [section("B", "two")]})) ==
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

    test "each supported subject returns something", %{entries: entries} do
      # The lexical pass only: embedding every topic would spend a round trip
      # per subject to prove something about the corpus, not about the network.
      for topic <- @topics, do: assert(Docs.lexical(topic, entries) != [], topic)
    end

    test "an off-topic question returns nothing", %{entries: entries} do
      for question <- [
            "zzzqqq unrelatedtoglific",
            "what is the weather in Mumbai today",
            "write me a poem about cats",
            "thanks!"
          ] do
        assert Docs.lexical(question, entries) == [], question
      end
    end

    test "both passes together answer a diagnosis question" do
      # The one test that runs the whole path. The provider is stubbed here
      # rather than in config, which would collide with the Req.Test ownership
      # other suites rely on.
      Application.put_env(:glific, :docs_embedding_request_options,
        req_http_options: [plug: Glific.Docs.StubEmbeddings]
      )

      on_exit(fn -> Application.delete_env(:glific, :docs_embedding_request_options) end)

      sections = Docs.find("why is my flow not triggering", limit: 5)

      assert Enum.any?(sections, &(&1.doc_file == @knowledge_base))
    end
  end

  defp section(heading, body) do
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
