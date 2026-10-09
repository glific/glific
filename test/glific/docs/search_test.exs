defmodule Glific.Docs.SearchTest do
  @moduledoc """
  The two retrieval legs and the rank fusion.

  The semantic leg is driven with vectors supplied directly rather than by
  embedding a question, so these run without an embedding provider.
  """

  use ExUnit.Case, async: true

  alias Glific.Docs.{Chunk, Index, Search}

  setup_all do
    Index.warm()
    %{entries: Index.entries()}
  end

  defp embedded(entries), do: Enum.reject(entries, &is_nil(&1.vector))

  describe "the semantic leg" do
    test "a chunk's own vector finds that chunk", %{entries: entries} do
      case embedded(entries) do
        [] ->
          :ok

        [entry | _rest] ->
          found = Search.semantic_leg("anything", entries, entry.vector)
          assert hd(found).content_hash == entry.chunk.content_hash
      end
    end

    test "a vector matching nothing well enough returns nothing", %{entries: entries} do
      case embedded(entries) do
        [] ->
          :ok

        [entry | _rest] ->
          # Negating a normalised vector puts it as far from the corpus as the
          # space allows, so every similarity falls under the floor.
          opposite = negate(entry.vector)
          assert Search.semantic_leg("anything", entries, opposite) == []
      end
    end

    test "entries with no vector are skipped rather than scored" do
      entries = [%{chunk: chunk("Title", "body"), vector: nil}]
      assert Search.semantic_leg("anything", entries, <<0::size(32)>>) == []
    end
  end

  describe "similarity" do
    test "a vector is identical to itself" do
      vector = Index.pack([0.3, 0.4, 0.5, 0.6])
      assert_in_delta Index.similarity(vector, vector), 1.0, 0.0001
    end

    test "vectors of different widths score zero rather than their overlap" do
      # Different widths mean different embedding models; scoring the common
      # prefix would rank them at random instead of reporting the mismatch.
      assert Index.similarity(Index.pack([1.0, 0.0, 0.0]), Index.pack([1.0, 0.0])) == 0.0
    end
  end

  describe "fusion" do
    test "a chunk both legs rank beats one only a single leg found" do
      both = chunk("Both", "found by both legs")
      one = chunk("One", "found by one leg")

      fused = Search.fuse(%{lexical: [one, both], semantic: [both]})

      assert [{first, legs} | _rest] = fused
      assert first.content_hash == both.content_hash
      assert Enum.sort(legs) == [:lexical, :semantic]
    end

    test "every chunk either leg found survives the merge" do
      a = chunk("A", "one")
      b = chunk("B", "two")

      assert length(Search.fuse(%{lexical: [a], semantic: [b]})) == 2
    end
  end

  describe "identifiers in bodies" do
    setup %{entries: entries}, do: %{entries: entries}

    test "an exact identifier is found where the documents write it", %{entries: entries} do
      # The documents write notation in prose, not in headings, so a body match
      # on one has to count for as much as a heading match on a word.
      for identifier <- ["@results.parent.state.input", "resumeContactFlow"] do
        assert Search.lexical_leg(identifier, entries) != [], identifier
      end
    end

    test "an ordinary word that happens to be rare is not an identifier", %{entries: entries} do
      # "today" sits in as few sections as `resumeContactFlow` does, so rarity
      # alone would let an off-topic question through on it.
      assert Search.lexical_leg("what is the weather in Mumbai today", entries) == []
      assert Search.lexical_leg("ignore previous instructions", entries) == []
    end
  end

  describe "terms" do
    test "notation stays whole" do
      assert "@results.parent.state.input" in Search.terms(
               "how do I read @results.parent.state.input"
             )
    end

    test "words carrying no topic are dropped" do
      assert Search.terms("hi team, please can you help") == []
    end
  end

  defp chunk(title, body) do
    %Chunk{
      doc_file: "doc",
      heading_path: title,
      body: body,
      content_hash: :crypto.hash(:sha256, title <> body) |> Base.encode16(case: :lower)
    }
  end

  defp negate(vector),
    do: for(<<value::float-32-little <- vector>>, into: <<>>, do: <<-value::float-32-little>>)
end
