defmodule Glific.Docs do
  @moduledoc """
  Glific's own documentation, split into sections and searched in memory.

  The markdown in `priv/docs_kb` is split on its headings, which is how the
  authors wrote it: a question as the heading, the answer under it.
  `Glific.AI.Tools.Documentation` hands the matching sections to the assistant.

  A question runs through two passes whose results merge by rank. The semantic
  pass matches meaning, so "the bot stopped replying" reaches "Flow is not
  triggering". The lexical pass matches exact text like
  `@results.parent.state.input`. Their scores are on different scales, so only
  the ranks are comparable.

  `mix glific.docs.index` writes the vectors to a build artifact that boot
  reads. Without it the sections are chunked at boot and only the lexical pass
  runs.
  """

  require Logger

  @documents ~w(glific_chatbot_knowledge_base glific_platform_guide glific_operations_manual)

  @index_key {__MODULE__, :entries}
  @metadata_key {__MODULE__, :metadata}
  @artifact "docs_kb/embeddings.etf"

  @typedoc "A heading, its prose, and the page it came from."
  @type chunk() :: %{
          doc_file: String.t(),
          section_path: String.t() | nil,
          heading_path: String.t(),
          body: String.t(),
          source_url: String.t() | nil,
          hash: String.t()
        }

  @typedoc "A chunk and its vector. `vector` is nil when no artifact was built."
  @type entry() :: %{chunk: chunk(), vector: binary() | nil}

  # Below this, a section is a label rather than an answer.
  @minimum_body 160
  @separator " › "

  # A table pairing user phrasings with section numbers. It matches almost any
  # question word for word, then points at a section instead of answering.
  @excluded_sections ["18"]

  # Sections written for Glific's engineers. An answer built from them sends
  # the reader to an internal API they cannot reach.
  @engineering ~r/lib\/glific\/|\.ex:\d|\bOban\b|\bEcto\b|defmodule|POST \/partner|\bpsql\b|\bJSONB\b/

  # Standard fusion constant: a section both passes rank beats one that only
  # a single pass found.
  @rrf_k 60
  @leg_depth 30

  # A heading states what its section answers.
  @heading_weight 4

  # Chapter 19 holds the corrections to commonly wrong answers.
  @boosted_sections ["19"]
  @boost_ranks 3

  # Without a floor each pass returns its full depth for any string at all.
  @minimum_similarity 0.45
  @minimum_overlap 5

  @stopwords MapSet.new(~w(
    the a an and or but if is are was were be been being of in on at to for
    with from by as it its this that these those i we you they he she them us
    my our your their can could will would should do does did have has had
    not no yes so then than there here what which who whom when where why how
    me am any all some more most other into about also very just only own same
    don now get got please hi hello thanks thank team need help issue problem
    having getting trying tried like want able there's i'm we're
  ))

  # ── Searching ──────────────────────────────────────────────────────────────

  @doc "The sections most likely to answer `question`, best first."
  @spec find(String.t(), keyword()) :: [chunk()]
  def find(question, opts \\ []) do
    entries = entries()

    %{
      lexical: lexical(question, entries),
      semantic: semantic(question, entries, opts[:query_vector])
    }
    |> fuse()
    |> Enum.take(Keyword.get(opts, :limit, 5))
  end

  @doc "The lexical pass on its own."
  @spec lexical(String.t(), [entry()]) :: [chunk()]
  def lexical(question, entries) do
    terms = terms(question)

    if terms == [] do
      []
    else
      floor = min(@minimum_overlap, @heading_weight * length(terms))
      identifiers = identifiers(question)

      entries
      |> Enum.map(&{overlap(&1.chunk, terms, identifiers), &1.chunk})
      |> Enum.filter(&(elem(&1, 0) >= floor))
      |> Enum.sort_by(fn {score, chunk} -> {-score, byte_size(chunk.body)} end)
      |> Enum.take(@leg_depth)
      |> Enum.map(&elem(&1, 1))
    end
  end

  @doc "The semantic pass on its own."
  @spec semantic(String.t(), [entry()], binary() | nil) :: [chunk()]
  def semantic(question, entries, query_vector \\ nil)
  def semantic(_question, [], _query_vector), do: []

  def semantic(question, entries, nil) do
    if Enum.any?(entries, & &1.vector) do
      case embed(question) do
        {:ok, vector} -> semantic(question, entries, vector)
        {:error, _reason} -> []
      end
    else
      []
    end
  end

  def semantic(_question, entries, vector) do
    entries
    |> Enum.reject(&is_nil(&1.vector))
    |> Enum.map(&{similarity(&1.vector, vector), &1.chunk})
    |> Enum.filter(&(elem(&1, 0) >= @minimum_similarity))
    |> Enum.sort_by(&(-elem(&1, 0)))
    |> Enum.take(@leg_depth)
    |> Enum.map(&elem(&1, 1))
  end

  @doc "Merges the passes by rank, each contributing `1 / (k + rank)`."
  @spec fuse(%{atom() => [chunk()]}) :: [chunk()]
  def fuse(passes) do
    passes
    |> Enum.reduce(%{}, fn {_pass, chunks}, acc ->
      chunks
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {chunk, rank}, inner ->
        contribution = 1.0 / (@rrf_k + max(rank - boost(chunk), 1))
        Map.update(inner, chunk.hash, {chunk, contribution}, &{chunk, elem(&1, 1) + contribution})
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.map(&elem(&1, 0))
  end

  @doc "The terms worth matching on. Notation stays whole, dots and all."
  @spec terms(String.t()) :: [String.t()]
  def terms(question) do
    ~r/[@a-z0-9][a-z0-9._\-]*/u
    |> Regex.scan(String.downcase(question))
    |> Enum.map(&(&1 |> List.first() |> String.trim(".")))
    |> Enum.reject(&(String.length(&1) < 2 or MapSet.member?(@stopwords, &1)))
    |> Enum.uniq()
  end

  @doc "The last heading in a chunk's trail."
  @spec title(chunk()) :: String.t()
  def title(chunk), do: chunk.heading_path |> String.split(@separator) |> List.last()

  defp overlap(chunk, terms, identifiers) do
    heading = String.downcase(chunk.heading_path)
    body = String.downcase(chunk.body)

    Enum.reduce(terms, 0, fn term, score ->
      cond do
        String.contains?(heading, term) -> score + @heading_weight
        String.contains?(body, term) -> score + body_weight(term, identifiers)
        true -> score
      end
    end)
  end

  # An identifier is exact: `@results.parent.state.input` means that string and
  # nothing else. The documents write identifiers in prose rather than in
  # headings, so a body match on one counts for as much as a heading match.
  defp body_weight(term, identifiers) do
    if MapSet.member?(identifiers, term), do: @heading_weight, else: 1
  end

  # Read before downcasing, which is where the camel hump would be lost.
  defp identifiers(question) do
    ~r/[@a-zA-Z0-9][a-zA-Z0-9._\-]*/u
    |> Regex.scan(question)
    |> Enum.map(&List.first/1)
    |> Enum.filter(&identifier?/1)
    |> MapSet.new(&(&1 |> String.downcase() |> String.trim(".")))
  end

  defp identifier?(token) do
    String.contains?(token, ".") or String.starts_with?(token, "@") or
      Regex.match?(~r/[a-z][A-Z]/, token)
  end

  defp boost(%{section_path: nil}), do: 0

  defp boost(%{section_path: path}) do
    if Enum.any?(@boosted_sections, &(path == &1 or String.starts_with?(path, &1 <> "."))),
      do: @boost_ranks,
      else: 0
  end

  # ── The index ──────────────────────────────────────────────────────────────

  @doc "Reads the artifact into `:persistent_term`, once, on boot."
  @spec warm() :: :ok
  def warm do
    {entries, metadata} = read_artifact()
    :persistent_term.put(@index_key, entries)
    :persistent_term.put(@metadata_key, metadata)
    :ok
  end

  @doc "Every indexed chunk with its vector."
  @spec entries() :: [entry()]
  def entries, do: :persistent_term.get(@index_key, nil) || elem(read_artifact(), 0)

  @doc "How many sections are indexed."
  @spec count() :: non_neg_integer()
  def count, do: length(entries())

  @doc "What the last build recorded about itself."
  @spec metadata() :: map()
  def metadata, do: :persistent_term.get(@metadata_key, nil) || elem(read_artifact(), 1)

  @doc "Where the build artifact lives."
  @spec artifact_path() :: String.t()
  def artifact_path, do: Application.app_dir(:glific, "priv/#{@artifact}")

  @doc "Writes entries to the artifact and to the in-memory copy."
  @spec write!([entry()], keyword()) :: :ok
  def write!(entries, metadata) do
    metadata = Map.new(metadata)
    payload = %{version: 1, metadata: metadata, entries: entries}

    File.write!(
      Path.join([File.cwd!(), "priv", @artifact]),
      :erlang.term_to_binary(payload, compressed: 6)
    )

    :persistent_term.put(@index_key, entries)
    :persistent_term.put(@metadata_key, metadata)
    :ok
  end

  @spec read_artifact() :: {[entry()], map()}
  defp read_artifact do
    case File.read(artifact_path()) do
      {:ok, binary} ->
        payload = :erlang.binary_to_term(binary)
        {Map.fetch!(payload, :entries), Map.get(payload, :metadata, %{})}

      {:error, reason} ->
        Logger.info("docs index not built (#{reason}); semantic search is disabled")
        {Enum.map(all_chunks(), &%{chunk: &1, vector: nil}), %{}}
    end
  end

  # ── Embedding ──────────────────────────────────────────────────────────────

  @doc "Embeds one piece of text, using the model and width the artifact holds."
  @spec embed(String.t()) :: {:ok, binary()} | {:error, term()}
  def embed(text) do
    metadata = metadata()
    model = Map.get(metadata, :model, model())
    dimensions = Map.get(metadata, :dimensions, dimensions())

    case ReqLLM.embed(model, text, embed_opts(dimensions)) do
      {:ok, floats} when is_list(floats) -> {:ok, pack(floats)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Normalises a vector of floats into the stored binary form."
  @spec pack([float()]) :: binary()
  def pack(floats) do
    magnitude = floats |> Enum.reduce(0.0, &(&2 + &1 * &1)) |> :math.sqrt()
    divisor = if magnitude == 0.0, do: 1.0, else: magnitude

    for value <- floats, into: <<>>, do: <<value / divisor::float-32-little>>
  end

  @doc "Cosine similarity of two packed vectors, or zero if their widths differ."
  @spec similarity(binary(), binary()) :: float()
  def similarity(left, right) when byte_size(left) == byte_size(right), do: dot(left, right, 0.0)
  def similarity(_left, _right), do: 0.0

  defp dot(<<>>, _right, acc), do: acc

  defp dot(<<a::float-32-little, left::binary>>, <<b::float-32-little, right::binary>>, acc),
    do: dot(left, right, acc + a * b)

  @doc "The embedding model the artifact is built with."
  @spec model() :: String.t()
  def model, do: config(:embedding_model, "openai:text-embedding-3-small")

  @doc "How many dimensions each stored vector has."
  @spec dimensions() :: pos_integer()
  def dimensions, do: config(:embedding_dimensions, 256)

  @doc "Request options for an embedding call."
  @spec embed_opts(pos_integer()) :: keyword()
  def embed_opts(dimensions) do
    [provider_options: [dimensions: dimensions]]
    |> then(&if(key = api_key(), do: Keyword.put(&1, :api_key, key), else: &1))
    |> Keyword.merge(Application.get_env(:glific, :docs_embedding_request_options, []))
  end

  # Glific holds this key as OPEN_AI_KEY, where req_llm looks for
  # OPENAI_API_KEY. Passed per call so no deployment sets it twice.
  defp api_key do
    case Application.get_env(:glific, :open_ai) do
      key when is_binary(key) and key != "This is not a secret" -> key
      _absent -> nil
    end
  end

  defp config(key, default),
    do: :glific |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)

  # ── Chunking ───────────────────────────────────────────────────────────────

  @doc "The documents that make up the corpus."
  @spec documents() :: [String.t()]
  def documents, do: @documents

  @doc "Every section of every document, less the ones kept out."
  @spec all_chunks() :: [chunk()]
  def all_chunks do
    @documents
    |> Enum.flat_map(fn document ->
      :glific
      |> Application.app_dir("priv/docs_kb/#{document}.md")
      |> File.read!()
      |> chunk(document)
    end)
    |> Enum.reject(&(excluded?(&1) or engineering?(&1)))
  end

  @doc "Whether a section is written for engineers rather than for chatbot staff."
  @spec engineering?(chunk()) :: boolean()
  def engineering?(%{body: body, heading_path: heading_path}),
    do: String.match?(body, @engineering) or String.match?(heading_path, @engineering)

  @doc "Splits markdown into sections on its headings."
  @spec chunk(String.t(), String.t()) :: [chunk()]
  def chunk(markdown, doc_file) when is_binary(markdown) and is_binary(doc_file) do
    markdown
    |> nodes()
    |> with_heading_paths()
    |> merge_small()
    |> Enum.map(&build_chunk(&1, doc_file))
    |> inherit_source_urls()
  end

  defp excluded?(%{section_path: nil}), do: false

  defp excluded?(%{section_path: path, doc_file: "glific_chatbot_knowledge_base"}),
    do: Enum.any?(@excluded_sections, &(path == &1 or String.starts_with?(path, &1 <> ".")))

  defp excluded?(_chunk), do: false

  defp nodes(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce({[], nil}, &collect/2)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.map(fn {level, title, lines} -> {level, title, Enum.reverse(lines)} end)
  end

  # A heading seen inside a code fence is part of the example.
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

  defp fence_marker(line) do
    case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, line) do
      [_, run] -> {String.first(run), String.length(run)}
      nil -> nil
    end
  end

  # A fence closes on its own character, at least as long, alone on the line.
  defp closes?(_open, nil, _line), do: false

  defp closes?({char, length}, {char, closing}, line) when closing >= length,
    do: String.trim(line) == String.duplicate(char, closing)

  defp closes?(_open, _marker, _line), do: false

  defp prepend([], _line), do: []
  defp prepend([{level, title, lines} | rest], line), do: [{level, title, [line | lines]} | rest]

  defp with_heading_paths(nodes) do
    nodes
    |> Enum.map_reduce([], fn {level, title, lines}, stack ->
      stack = Enum.take_while(stack, fn {ancestor, _} -> ancestor < level end) ++ [{level, title}]
      {%{level: level, title: title, lines: lines, trail: Enum.map(stack, &elem(&1, 1))}, stack}
    end)
    |> elem(0)
  end

  # Into an ancestor only; folding into a sibling joins two unrelated answers.
  defp merge_small(nodes) do
    nodes
    |> Enum.reduce([], fn node, kept ->
      text = node.lines |> Enum.join("\n") |> String.trim()

      cond do
        text == "" -> kept
        byte_size(text) >= @minimum_body -> [node | kept]
        ancestor?(kept, node) -> [fold(hd(kept), node) | tl(kept)]
        true -> [node | kept]
      end
    end)
    |> Enum.reverse()
  end

  defp fold(parent, node), do: %{parent | lines: parent.lines ++ ["", node.title] ++ node.lines}

  defp ancestor?([%{level: level} | _], %{level: node_level}), do: level < node_level
  defp ancestor?([], _node), do: false

  defp build_chunk(node, doc_file) do
    body = node.lines |> Enum.join("\n") |> String.trim()
    heading_path = Enum.join(node.trail, @separator)

    %{
      doc_file: doc_file,
      section_path: section_path(node.title),
      heading_path: heading_path,
      body: body,
      source_url: source_url(body),
      hash: :sha256 |> :crypto.hash(heading_path <> body) |> Base.encode16(case: :lower)
    }
  end

  # The documents cross-reference each other by section number.
  defp section_path(title) do
    case Regex.run(~r/^(\d+(?:\.\d+)*)[.\s]/, title) do
      [_, number] -> number
      nil -> nil
    end
  end

  defp source_url(body) do
    case Regex.run(~r/Source:\s*(https?:\/\/\S+)/u, body) do
      [_, url] -> url
      nil -> nil
    end
  end

  # A page states its source once; later sections take the nearest one above.
  defp inherit_source_urls(chunks) do
    chunks
    |> Enum.map_reduce(nil, fn chunk, nearest ->
      url = chunk.source_url || nearest
      {%{chunk | source_url: url}, url}
    end)
    |> elem(0)
  end
end
