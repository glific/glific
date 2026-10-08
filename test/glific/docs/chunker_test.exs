defmodule Glific.Docs.ChunkerTest do
  @moduledoc """
  The chunker, run against the shipped knowledge base.

  Real sections rather than invented markdown: an invented document agrees with
  whatever the parser happens to do.
  """

  use ExUnit.Case, async: true

  alias Glific.Docs.{Chunk, Chunker}

  @knowledge_base "glific_chatbot_knowledge_base"

  setup_all do
    path = Application.app_dir(:glific, "priv/docs_kb/#{@knowledge_base}.md")
    markdown = File.read!(path)
    %{markdown: markdown, chunks: Chunker.chunk(markdown, @knowledge_base)}
  end

  defp find(chunks, section_path),
    do: Enum.find(chunks, &(&1.section_path == section_path))

  describe "splitting" do
    test "the knowledge base splits into roughly its heading count", %{chunks: chunks} do
      assert length(chunks) > 100
      assert length(chunks) < 200
    end

    test "every chunk carries a trail, a body and a hash", %{chunks: chunks} do
      for chunk <- chunks do
        assert chunk.heading_path != ""
        assert String.trim(chunk.body) != ""
        assert chunk.content_hash =~ ~r/^[0-9a-f]{64}$/
        assert chunk.doc_file == @knowledge_base
      end
    end

    test "the hash changes when the body does", %{chunks: chunks} do
      chunk = hd(chunks)
      [edited] = Chunker.chunk("## #{Chunk.title(chunk)}\n\n#{chunk.body} and one more word", "x")
      refute edited.content_hash == chunk.content_hash
    end

    test "chunking is deterministic", %{markdown: markdown, chunks: chunks} do
      assert Chunker.chunk(markdown, @knowledge_base) == chunks
    end
  end

  describe "3.4 — the parent variable section the mapping table points at" do
    test "it is one chunk, not split across its two examples", %{chunks: chunks} do
      chunk = find(chunks, "3.4")

      assert chunk.heading_path =~ "parent flow"
      assert chunk.body =~ "@results.parent.<variable_name>.input"
      assert chunk.body =~ "@results.parent.state.input"
    end

    test "its heading trail carries the chapter above it", %{chunks: chunks} do
      chunk = find(chunks, "3.4")
      assert chunk.heading_path =~ "›"
      assert Chunk.title(chunk) =~ "3.4"
    end

    test "the embedded text leads with the trail, so the topic is stated", %{chunks: chunks} do
      chunk = find(chunks, "3.4")
      text = Chunk.embed_text(chunk)

      assert String.starts_with?(text, chunk.heading_path)
      assert text =~ "@results.parent"
    end

    test "3.5 is a separate chunk, so parent and child do not merge", %{chunks: chunks} do
      assert find(chunks, "3.5").body =~ "@results.child"
      refute find(chunks, "3.4").body =~ "@results.child"
    end
  end

  describe "7.6 — a short section that must survive on its own" do
    test "it is kept rather than merged, and still says no", %{chunks: chunks} do
      chunk = find(chunks, "7.6")

      assert Chunk.title(chunk) =~ "approved template"
      assert chunk.body =~ "No."
      refute chunk.body =~ "7.7"
    end
  end

  describe "source urls" do
    test "the url on the heading line is parsed off", %{chunks: chunks} do
      assert find(chunks, "3.4").source_url =~ "Parent%20and%20Child%20variable"
    end

    test "every url is a url", %{chunks: chunks} do
      for chunk <- chunks, chunk.source_url do
        assert chunk.source_url =~ ~r{^https?://}
      end
    end

    test "a section with no source of its own inherits the nearest above it" do
      markdown = """
      ## 1.1 First

      📖 Source: https://example.com/page

      #{String.duplicate("Body text that is long enough to stand alone. ", 6)}

      ## 1.2 Second

      #{String.duplicate("A later section on the same page states no source. ", 6)}
      """

      assert [first, second] = Chunker.chunk(markdown, "doc")
      assert first.source_url == "https://example.com/page"
      assert second.source_url == "https://example.com/page"
    end
  end

  describe "code fences" do
    test "a longer fence is not closed by a shorter one" do
      markdown = """
      ## 1.1 Nested example

      #{String.duplicate("Prose long enough for this section to stand alone. ", 5)}

      ````markdown
      ```elixir
      # still inside the outer fence
      ```
      ## Not a heading
      ````

      #{String.duplicate("Prose after the example, also long enough. ", 5)}
      """

      assert [chunk] = Chunker.chunk(markdown, "doc")
      assert chunk.body =~ "## Not a heading"
      assert chunk.body =~ "Prose after the example"
    end

    test "a tilde fence hides a heading too" do
      markdown = """
      ## 1.1 Tilde example

      #{String.duplicate("Prose long enough for this section to stand alone. ", 5)}

      ~~~
      ## Not a heading either
      ~~~

      #{String.duplicate("Prose after the example, also long enough. ", 5)}
      """

      assert [chunk] = Chunker.chunk(markdown, "doc")
      assert chunk.body =~ "## Not a heading either"
    end

    test "a # inside a fence is not a heading" do
      markdown = """
      ## 1.1 Running the indexer

      #{String.duplicate("Prose before the example that is long enough to stand. ", 5)}

      ```bash
      # this is a shell comment, not a heading
      mix glific.docs.index
      ```

      #{String.duplicate("Prose after the example, also long enough to stand. ", 5)}
      """

      assert [chunk] = Chunker.chunk(markdown, "doc")
      assert chunk.body =~ "# this is a shell comment"
      assert chunk.body =~ "mix glific.docs.index"
      assert chunk.body =~ "Prose after the example"
    end

    test "no fence in the shipped corpus is left unclosed by the split", %{chunks: chunks} do
      for chunk <- chunks do
        fences = chunk.body |> String.split("```") |> length() |> Kernel.-(1)
        assert rem(fences, 2) == 0, "unbalanced fence in #{chunk.heading_path}"
      end
    end
  end

  describe "merging small sections" do
    test "a label-sized child folds into its parent, keeping its heading" do
      markdown = """
      ## 2.1 Limits

      #{String.duplicate("The parent section carries the real explanation here. ", 6)}

      ### 2.1.1 Image

      5 MB.

      ### 2.1.2 Video

      16 MB.
      """

      assert [chunk] = Chunker.chunk(markdown, "doc")
      assert chunk.body =~ "5 MB."
      assert chunk.body =~ "16 MB."
      assert chunk.body =~ "2.1.1 Image"
    end

    test "a heading with no body at all is dropped, but stays in the trail" do
      markdown = """
      # 3. Flow Variables

      ## 3.1 Saving input

      #{String.duplicate("A real answer with enough text to stand on its own. ", 6)}
      """

      assert [chunk] = Chunker.chunk(markdown, "doc")
      assert chunk.heading_path == "3. Flow Variables › 3.1 Saving input"
    end

    test "two small siblings stay apart rather than gluing together" do
      markdown = """
      ## 4.1 One

      Short.

      ## 4.2 Two

      Also short.
      """

      chunks = Chunker.chunk(markdown, "doc")
      assert length(chunks) == 2
      refute hd(chunks).body =~ "Also short"
    end
  end

  describe "the other shipped documents" do
    for document <- ~w(glific_platform_guide glific_operations_manual) do
      test "#{document} chunks without losing its headings" do
        document = unquote(document)
        path = Application.app_dir(:glific, "priv/docs_kb/#{document}.md")
        chunks = path |> File.read!() |> Chunker.chunk(document)

        assert chunks != []
        assert Enum.all?(chunks, &(String.trim(&1.body) != ""))
        assert Enum.all?(chunks, &(&1.doc_file == document))
      end
    end
  end
end
