defmodule Glific.Docs do
  @moduledoc """
  Glific's own documentation, searched in memory.

  Each document in `priv/docs_kb` is a run of entries. An entry opens with
  `--- entry`, states its heading and page, and then answers one question —
  the boundaries are written down rather than worked out from the markdown.
  `Glific.AI.Tools.Documentation` hands the matching entries to the assistant.

  A question runs through two passes whose results merge by rank. The semantic
  pass matches meaning, so "the bot stopped replying" reaches "Flow is not
  triggering". The lexical pass matches exact text like
  `@results.parent.state.input`. Their scores are on different scales, so only
  the ranks are comparable.

  `mix glific.docs.index` writes the vectors to a build artifact that boot
  reads. Without it the documents are read at boot and only the lexical pass
  runs.
  """

  require Logger

  alias Glific.SafeLog

  @index_key {__MODULE__, :entries}
  @metadata_key {__MODULE__, :metadata}
  @corpus "docs_kb"
  @artifact "docs_kb/embeddings.etf"
  @version 1

  @typedoc "One section of documentation: a heading, its prose, and its page."
  @type section() :: %{
          doc_file: String.t(),
          section_path: String.t() | nil,
          heading_path: String.t(),
          body: String.t(),
          source_url: String.t() | nil,
          hash: String.t()
        }

  @typedoc "An indexed section. `vector` is nil when no artifact was built."
  @type entry() :: %{section: section(), vector: binary() | nil}

  @separator " › "

  # Reciprocal rank fusion. 60 is the constant the method is usually used with;
  # it makes a section both passes rank beat one that only a single pass found.
  @rrf_k 60

  # How many candidates each pass offers the merge.
  @candidates 30

  # A heading states what its section answers.
  @heading_weight 4

  # Without a floor each pass returns candidates for any string at all. Both
  # numbers were measured: they sit between what an off-topic question scores
  # and what a real one does.
  @minimum_similarity 0.45

  # Longer than any real identifier, and past what a pasted dump can compile to.
  @longest_term 128

  # A question this short cannot reach @minimum_overlap on body text alone, so
  # it qualifies on terms matched rather than on score. Separate from the floor
  # because it counts a different thing: raising one should not move the other.
  @short_question 4

  # Two headings named. Enough to say a section is about what was asked even
  # with a term unaccounted for, and out of reach of one heading plus a word
  # that merely occurs in prose.
  @strong_partial 8
  @minimum_overlap 5

  @stopwords MapSet.new(~w(
    the a an and or but if is are was were be been being of in on at to for
    with from by as it its this that these those i we you they he she them us
    my our your their can could will would should do does did have has had
    not no yes so then than there here what which who whom when where why how
    me am any all some more most other into about also very just only own same
    don now get got please hi hello thanks thank team need help issue problem
    having getting trying tried like want able
  ))

  @doc "Every document in `priv/docs_kb`, by name."
  @spec documents() :: [String.t()]
  def documents do
    paths() |> Enum.map(&Path.basename(&1, ".md")) |> Enum.sort()
  end

  defp paths do
    :glific |> Application.app_dir("priv/#{@corpus}") |> Path.join("*.md") |> Path.wildcard()
  end

  @doc "Every entry of every document."
  @spec sections() :: [section()]
  def sections do
    Enum.flat_map(paths(), fn path ->
      path |> File.read!() |> parse(Path.basename(path, ".md"))
    end)
  end

  @doc """
  Splits a document into its entries.

  Each begins with `--- entry`, then `key: value` lines, then `---`, then the
  prose. The boundaries are written down rather than worked out from the
  headings, so a document says where its answers start and stop.
  """
  @spec parse(String.t(), String.t()) :: [section()]
  def parse(text, document) do
    text
    |> String.split(~r/^--- entry\s*$/m, trim: true)
    |> Enum.map(&entry(&1, document))
    |> Enum.reject(&is_nil/1)
  end

  defp entry(block, document) do
    case String.split(block, ~r/^---\s*$/m, parts: 2) do
      [front, body] -> build(front, trim_body(body), document)
      _no_front_matter -> nil
    end
  end

  # An entry ends where the next begins, so the rule that separated them in
  # the file is not part of the answer.
  defp trim_body(body) do
    body |> String.trim() |> String.replace(~r/\n\s*-{3,}\s*$/, "") |> String.trim()
  end

  defp build(front, body, document) do
    fields =
      front
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, ":"))
      |> Map.new(fn line ->
        [key, value] = String.split(line, ":", parts: 2)
        {String.trim(key), String.trim(value)}
      end)

    heading = Map.get(fields, "heading", "")

    # An entry that is only its source line answers nothing, and the lexical
    # pass breaks ties on the shortest body, so it would outrank the section
    # that does answer.
    prose = body |> String.replace(~r/📖 Source:\s*\S+/u, "") |> String.trim()

    if heading == "" or prose == "" do
      nil
    else
      %{
        doc_file: document,
        section_path: Map.get(fields, "section"),
        heading_path: heading,
        body: body,
        source_url: Map.get(fields, "source"),
        hash: :sha256 |> :crypto.hash(heading <> body) |> Base.encode16(case: :lower)
      }
    end
  end

  @doc "Reads the artifact into `:persistent_term`, once, on boot."
  @spec warm() :: :ok
  def warm do
    artifact = read_artifact()
    :persistent_term.put(@index_key, artifact.entries)
    :persistent_term.put(@metadata_key, artifact.metadata)
    :ok
  end

  @doc "Every indexed section with its vector."
  @spec entries() :: [entry()]
  def entries, do: :persistent_term.get(@index_key, nil) || read_artifact().entries

  @doc "How many sections are indexed."
  @spec count() :: non_neg_integer()
  def count, do: length(entries())

  @doc "What the last build recorded about itself."
  @spec metadata() :: map()
  def metadata, do: :persistent_term.get(@metadata_key, nil) || read_artifact().metadata

  @doc "Where the build artifact lives."
  @spec artifact_path() :: String.t()
  def artifact_path,
    do: config(:artifact_path, Application.app_dir(:glific, "priv/#{@artifact}"))

  @doc "Writes entries to the artifact and to the in-memory copy."
  @spec write!([entry()], keyword()) :: :ok
  def write!(entries, metadata) do
    metadata = Map.new(metadata)
    payload = %{version: @version, metadata: metadata, entries: entries}

    File.write!(artifact_path(), :erlang.term_to_binary(payload, compressed: 6))

    :persistent_term.put(@index_key, entries)
    :persistent_term.put(@metadata_key, metadata)
    :ok
  end

  # Read with `:safe`, which refuses to create atoms. Everything the artifact
  # holds is named somewhere in this module, so the atoms already exist.
  @spec read_artifact() :: %{entries: [entry()], metadata: map()}
  defp read_artifact do
    with {:ok, binary} <- File.read(artifact_path()),
         %{version: @version, entries: entries} = payload <-
           :erlang.binary_to_term(binary, [:safe]) do
      %{entries: entries, metadata: Map.get(payload, :metadata, %{})}
    else
      other ->
        Logger.warning(
          "docs index unusable (#{SafeLog.safe_inspect(other)}); searching without vectors"
        )

        without_vectors()
    end
  rescue
    exception ->
      Logger.warning("docs index unreadable (#{Exception.message(exception)})")
      without_vectors()
  end

  # The lexical pass still works without an artifact; the semantic one cannot.
  defp without_vectors,
    do: %{entries: Enum.map(sections(), &%{section: &1, vector: nil}), metadata: %{}}

  @doc "Embeds one piece of text, using the model and width the artifact holds."
  @spec embed(String.t()) :: {:ok, binary()} | {:error, term()}
  def embed(text) do
    metadata = metadata()
    model = Map.get(metadata, :model, model())
    dimensions = Map.get(metadata, :dimensions, dimensions())

    case ReqLLM.embed(model, text, embed_opts(dimensions, model)) do
      {:ok, floats} when is_list(floats) -> {:ok, pack(floats)}
      other -> {:error, other}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
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
  @spec embed_opts(pos_integer(), String.t() | nil) :: keyword()
  def embed_opts(dimensions, model \\ nil) do
    [provider_options: [dimensions: dimensions]]
    |> then(&if(key = api_key(model), do: Keyword.put(&1, :api_key, key), else: &1))
    |> Keyword.merge(Application.get_env(:glific, :docs_embedding_request_options, []))
  end

  # Glific holds this key as OPEN_AI_KEY, where req_llm looks for
  # OPENAI_API_KEY. Passed per call so no deployment sets it twice, and only
  # to OpenAI: another provider must not be handed someone else's key.
  defp api_key(model) do
    with true <- String.starts_with?(model || model(), "openai:"),
         key when is_binary(key) and key != "This is not a secret" <- Glific.get_open_ai_key() do
      key
    else
      _other -> nil
    end
  end

  defp config(key, default),
    do: :glific |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)

  @doc "The sections most likely to answer `question`, best first."
  @spec find(String.t(), keyword()) :: [section()]
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
  @spec lexical(String.t(), [entry()]) :: [section()]
  def lexical(question, entries) do
    terms = terms(question)

    if terms == [] do
      []
    else
      identifiers = identifiers(question)
      patterns = matchers(terms, identifiers)

      entries
      |> Enum.map(&{overlap(&1.section, patterns, identifiers), &1.section})
      |> Enum.filter(&keep?(&1, length(terms)))
      |> Enum.sort_by(fn {{score, _matched}, section} -> {-score, byte_size(section.body)} end)
      |> Enum.take(@candidates)
      |> Enum.map(&elem(&1, 1))
    end
  end

  @doc "The semantic pass on its own."
  @spec semantic(String.t(), [entry()], binary() | nil) :: [section()]
  def semantic(question, entries, query_vector \\ nil)
  def semantic(_question, [], _query_vector), do: []

  def semantic(question, entries, nil) do
    if Enum.any?(entries, & &1.vector) do
      case embed(question) do
        {:ok, vector} ->
          semantic(question, entries, vector)

        {:error, reason} ->
          Logger.warning(
            "docs question not embedded (#{SafeLog.safe_inspect(reason)}); lexical only"
          )

          []
      end
    else
      []
    end
  end

  def semantic(_question, entries, vector) do
    entries
    |> Enum.reject(&is_nil(&1.vector))
    |> Enum.map(&{similarity(&1.vector, vector), &1.section})
    |> Enum.filter(&(elem(&1, 0) >= @minimum_similarity))
    |> Enum.sort_by(&(-elem(&1, 0)))
    |> Enum.take(@candidates)
    |> Enum.map(&elem(&1, 1))
  end

  @doc "Merges the passes by rank, each contributing `1 / (k + rank)`."
  @spec fuse(%{atom() => [section()]}) :: [section()]
  def fuse(passes) do
    passes
    |> Enum.reduce(%{}, fn {_pass, found}, acc ->
      found
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {section, rank}, inner ->
        contribution = 1.0 / (@rrf_k + rank)

        Map.update(
          inner,
          section.hash,
          {section, contribution},
          &{section, elem(&1, 1) + contribution}
        )
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.map(&elem(&1, 0))
  end

  @doc "The terms worth matching on. Notation stays whole, dots and all."
  @spec terms(String.t()) :: [String.t()]
  def terms(question) do
    ~r/[@\p{L}\p{N}][\p{L}\p{M}\p{N}._\-]*/u
    |> Regex.scan(String.downcase(question))
    |> Enum.map(&(&1 |> List.first() |> String.trim(".")))
    |> Enum.reject(
      &(String.length(&1) < 2 or String.length(&1) > @longest_term or
          MapSet.member?(@stopwords, &1))
    )
    |> Enum.uniq()
  end

  @doc "The last heading in a section's trail."
  @spec title(section()) :: String.t()
  def title(section), do: section.heading_path |> String.split(@separator) |> List.last()

  # How many terms a question has decides what it can score, so each length
  # qualifies its own way. One word says too little to trust where it appears
  # in prose alone, so it has to name the section or be an identifier. Too few
  # words to reach @minimum_overlap on body text — a pasted error string — must
  # match every term they have instead. Longer questions clear the floor on
  # weight alone.
  defp keep?({{score, _matched}, _section}, 1), do: score >= @heading_weight

  defp keep?({{score, matched}, _section}, count) when count <= @short_question,
    do: matched == count or score >= @strong_partial

  defp keep?({{score, _matched}, _section}, _count), do: score >= @minimum_overlap

  defp overlap(section, terms, identifiers) do
    heading = String.downcase(section.heading_path)
    body = String.downcase(section.body)

    Enum.reduce(terms, {0, 0}, fn {term, pattern}, {score, matched} ->
      cond do
        Regex.match?(pattern, heading) -> {score + @heading_weight, matched + 1}
        Regex.match?(pattern, body) -> {score + body_weight(term, identifiers), matched + 1}
        true -> {score, matched}
      end
    end)
  end

  defp matchers(terms, identifiers) do
    Enum.map(terms, fn term ->
      # An identifier means that string and nothing else, so it takes no
      # plural: `@results.parent.state.input` is not the `.inputs` of some
      # other notation. Ordinary words are written both ways in the documents.
      plural = if MapSet.member?(identifiers, term), do: "", else: "(?:e?s)?"

      # A dot carries notation on, so `@contact` is no match for `@contact.id`
      # — but only where something follows it, the dot ending a sentence being
      # punctuation. Nothing guards the near side on purpose: the documents
      # write a field as `@contact.optin_status` far more often than bare, and
      # that is the section someone pasting the name is looking for.
      pattern =
        "(?<![\\p{L}\\p{N}_])" <>
          Regex.escape(term) <> plural <> "(?![\\p{L}\\p{N}_])(?!\\.[\\p{L}\\p{N}_])"

      {term, Regex.compile!(pattern, "u")}
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
    ~r/[@\p{L}\p{N}][\p{L}\p{M}\p{N}._\-]*/u
    |> Regex.scan(question)
    |> Enum.map(&(&1 |> List.first() |> String.trim(".")))
    |> Enum.filter(&identifier?/1)
    |> MapSet.new(&String.downcase/1)
  end

  defp identifier?(token) do
    String.contains?(token, ".") or String.contains?(token, "_") or
      String.starts_with?(token, "@") or Regex.match?(~r/[a-z][A-Z]/, token)
  end
end
