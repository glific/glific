defmodule Glific.Docs.Chunker do
  @moduledoc """
  Splits a documentation file into `Glific.Docs.Chunk`s on its markdown headings.

  Each section is already written as one self-contained answer, so the heading
  is the split point. Three details the markdown requires:

    * A `#` inside a code fence is part of the example, not a heading.
    * A page states its `📖 Source:` once, so a section without one takes the
      nearest URL above it.
    * A heading with a line or two under it is a label, and merges into its
      parent.

  Pure function: same markdown in, same chunks out.
  """

  alias Glific.Docs.Chunk

  # Below this, a section is a label rather than an answer.
  @minimum_body 160

  @separator " › "

  @doc "Splits markdown into chunks. `doc_file` is carried onto each one."
  @spec chunk(String.t(), String.t()) :: [Chunk.t()]
  def chunk(markdown, doc_file) when is_binary(markdown) and is_binary(doc_file) do
    markdown
    |> nodes()
    |> with_heading_paths()
    |> merge_small()
    |> Enum.map(&build(&1, doc_file))
    |> inherit_source_urls()
  end

  @spec nodes(String.t()) :: [{pos_integer(), String.t(), [String.t()]}]
  defp nodes(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce({[], nil}, &collect/2)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.map(fn {level, title, lines} -> {level, title, Enum.reverse(lines)} end)
  end

  # `{nodes, open_fence}` — a heading seen inside a fence is example text.
  defp collect(line, {acc, fence}) do
    marker = fence_marker(line)

    cond do
      is_nil(fence) and marker != nil ->
        {prepend(acc, line), marker}

      fence != nil ->
        {prepend(acc, line), if(closes?(fence, marker, line), do: nil, else: fence)}

      Regex.run(~r/^(\#+)\s+(\S.*)$/, line) != nil ->
        [_, hashes, title] = Regex.run(~r/^(\#+)\s+(\S.*)$/, line)
        {[{String.length(hashes), String.trim(title), []} | acc], fence}

      true ->
        {prepend(acc, line), fence}
    end
  end

  @spec fence_marker(String.t()) :: {String.t(), pos_integer()} | nil
  defp fence_marker(line) do
    case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, line) do
      [_, run] -> {String.first(run), String.length(run)}
      nil -> nil
    end
  end

  # A fence closes only on its own character, at least as long, and alone on its line.
  defp closes?(_open, nil, _line), do: false

  defp closes?({char, length}, {char, closing}, line) when closing >= length,
    do: String.trim(line) == String.duplicate(char, closing)

  defp closes?(_open, _marker, _line), do: false

  defp prepend([], _line), do: []
  defp prepend([{level, title, lines} | rest], line), do: [{level, title, [line | lines]} | rest]

  @spec with_heading_paths([{pos_integer(), String.t(), [String.t()]}]) :: [map()]
  defp with_heading_paths(nodes) do
    nodes
    |> Enum.map_reduce([], fn {level, title, lines}, stack ->
      stack = Enum.take_while(stack, fn {ancestor, _} -> ancestor < level end) ++ [{level, title}]
      node = %{level: level, title: title, lines: lines, trail: Enum.map(stack, &elem(&1, 1))}
      {node, stack}
    end)
    |> elem(0)
  end

  # Merges only into an ancestor; folding into the previous sibling would join
  # two unrelated answers.
  @spec merge_small([map()]) :: [map()]
  defp merge_small(nodes) do
    nodes
    |> Enum.reduce([], fn node, kept ->
      text = node.lines |> Enum.join("\n") |> String.trim()

      cond do
        text == "" ->
          kept

        byte_size(text) >= @minimum_body ->
          [node | kept]

        ancestor?(kept, node) ->
          [parent | rest] = kept
          [%{parent | lines: parent.lines ++ ["", node.title] ++ node.lines} | rest]

        true ->
          [node | kept]
      end
    end)
    |> Enum.reverse()
  end

  @spec ancestor?([map()], map()) :: boolean()
  defp ancestor?([%{level: level} | _], %{level: node_level}), do: level < node_level
  defp ancestor?([], _node), do: false

  @spec build(map(), String.t()) :: Chunk.t()
  defp build(node, doc_file) do
    body = node.lines |> Enum.join("\n") |> String.trim()
    heading_path = Enum.join(node.trail, @separator)

    %Chunk{
      doc_file: doc_file,
      section_path: section_path(node.title),
      heading_path: heading_path,
      body: body,
      source_url: source_url(body),
      content_hash: hash(heading_path, body)
    }
  end

  # The documents cross-reference each other by section number alone.
  @spec section_path(String.t()) :: String.t() | nil
  defp section_path(title) do
    case Regex.run(~r/^(\d+(?:\.\d+)*)[.\s]/, title) do
      [_, number] -> number
      nil -> nil
    end
  end

  @spec source_url(String.t()) :: String.t() | nil
  defp source_url(body) do
    case Regex.run(~r/Source:\s*(https?:\/\/\S+)/u, body) do
      [_, url] -> url
      nil -> nil
    end
  end

  # A page states its source once, so later sections take the nearest one above.
  @spec inherit_source_urls([Chunk.t()]) :: [Chunk.t()]
  defp inherit_source_urls(chunks) do
    chunks
    |> Enum.map_reduce(nil, fn chunk, nearest ->
      url = chunk.source_url || nearest
      {%{chunk | source_url: url}, url}
    end)
    |> elem(0)
  end

  @spec hash(String.t(), String.t()) :: String.t()
  defp hash(heading_path, body),
    do: :crypto.hash(:sha256, heading_path <> body) |> Base.encode16(case: :lower)
end
