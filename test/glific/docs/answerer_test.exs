defmodule Glific.Docs.AnswererTest do
  @moduledoc """
  The context block handed to the model. Generating an answer needs a provider,
  so what is covered here is how the context is assembled.
  """

  use ExUnit.Case, async: true

  alias Glific.Docs.{Answerer, Chunk}

  defp result(title, body, url \\ nil) do
    %{
      chunk: %Chunk{
        doc_file: "doc",
        heading_path: title,
        body: body,
        source_url: url,
        content_hash: "hash-#{title}"
      },
      rank: 1,
      legs: [:lexical]
    }
  end

  test "each section carries its title and the page it came from" do
    context = Answerer.context([result("7.6 Editing a template", "No.", "https://example.com/a")])

    assert context =~ "[7.6 Editing a template]"
    assert context =~ "(https://example.com/a)"
    assert context =~ "No."
  end

  test "a section with no source url is still included" do
    assert Answerer.context([result("Untitled", "body")]) =~ "body"
  end

  test "sections are separated so the model can tell them apart" do
    context = Answerer.context([result("A", "first"), result("B", "second")])

    assert context =~ "first"
    assert context =~ "second"
    assert context =~ "---"
  end

  test "a long section is cut, and the cut leaves valid text" do
    # A multibyte character spanning the byte limit would otherwise leave an
    # invalid suffix in the prompt. The corpus is full of › — ’ and 📖.
    body = String.duplicate("सन्दर्भ 📖 ", 400)
    context = Answerer.context([result("Long", body)])

    assert String.valid?(context)
    assert context =~ "section continues"
    assert byte_size(context) < byte_size(body)
  end

  test "a section under the limit is passed through whole" do
    assert Answerer.context([result("Short", "a short body")]) =~ "a short body"
    refute Answerer.context([result("Short", "a short body")]) =~ "section continues"
  end
end
