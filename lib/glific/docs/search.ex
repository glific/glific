defmodule Glific.Docs.Search do
  @moduledoc """
  Finds the documentation chunks that answer a question.

  Two retrievers run over the corpus and are merged. The semantic leg matches
  wording that shares no words with the section — "the bot stopped replying"
  against "Flow is not triggering". The lexical leg matches exact tokens like
  `@results.parent.state.input`, which an embedding blurs.

  They merge by rank rather than by score: cosine similarity and term overlap
  are not on the same scale, so there is no fixed weighting between them.
  """

  alias Glific.Docs.{Chunk, Index, Indexer}

  # Standard reciprocal-rank-fusion constant: a chunk ranked well by both legs
  # beats one ranked first by a single leg.
  @rrf_k 60

  @leg_depth 30

  # Floors, without which either leg answers any string at all. An off-topic
  # question tops out near 0.44 cosine and 4 points of overlap, where a real one
  # starts around 0.52 and 5: one stray word — "today" against a calendar
  # section — is a point of overlap and nothing more.
  @minimum_similarity 0.45
  @minimum_overlap 5

  # A heading states what its section answers.
  @heading_weight 4

  # Chapter 19 holds the corrections to commonly wrong answers.
  @boosted_sections ["19"]
  @boost_ranks 3

  @stopwords MapSet.new(~w(
    the a an and or but if is are was were be been being of in on at to for
    with from by as it its this that these those i we you they he she them us
    my our your their can could will would should do does did have has had
    not no yes so then than there here what which who whom when where why how
    me am any all some more most other into about also very just only own same
    don now get got please hi hello thanks thank team need help issue problem
    having getting trying tried like want able there's i'm we're
  ))

  @type result() :: %{chunk: Chunk.t(), rank: pos_integer(), legs: [atom()]}

  @doc """
  Returns the chunks most likely to answer `question`, best first.

  Falls back to the lexical leg alone when no embedding is available.
  """
  @spec find(String.t(), keyword()) :: [result()]
  def find(question, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    entries = Index.entries()

    lexical = lexical_leg(question, entries)
    semantic = semantic_leg(question, entries, Keyword.get(opts, :query_vector))

    fuse(%{lexical: lexical, semantic: semantic})
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {{chunk, legs}, rank} -> %{chunk: chunk, rank: rank, legs: legs} end)
  end

  @doc """
  The lexical leg on its own.

  A one-word query is held to a heading match rather than to the full floor,
  since that is the most it can score.
  """
  @spec lexical_leg(String.t(), [Index.entry()]) :: [Chunk.t()]
  def lexical_leg(question, entries) do
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

  @doc "The semantic leg on its own."
  @spec semantic_leg(String.t(), [Index.entry()], binary() | nil) :: [Chunk.t()]
  def semantic_leg(question, entries, query_vector \\ nil)
  def semantic_leg(_question, [], _query_vector), do: []

  def semantic_leg(question, entries, nil) do
    if Enum.any?(entries, & &1.vector) do
      case Indexer.embed(question) do
        {:ok, vector} -> semantic_leg(question, entries, vector)
        {:error, _reason} -> []
      end
    else
      []
    end
  end

  def semantic_leg(_question, entries, vector) do
    entries
    |> Enum.reject(&is_nil(&1.vector))
    |> Enum.map(&{Index.similarity(&1.vector, vector), &1.chunk})
    |> Enum.filter(&(elem(&1, 0) >= @minimum_similarity))
    |> Enum.sort_by(&(-elem(&1, 0)))
    |> Enum.take(@leg_depth)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Reciprocal rank fusion of named result lists.

  Each list contributes `1 / (k + rank)` to every chunk it ranks.
  """
  @spec fuse(%{atom() => [Chunk.t()]}) :: [{Chunk.t(), [atom()]}]
  def fuse(legs) do
    legs
    |> Enum.reduce(%{}, fn {leg, chunks}, acc ->
      chunks
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {chunk, rank}, inner ->
        rank = rank - boost(chunk)
        contribution = 1.0 / (@rrf_k + max(rank, 1))

        Map.update(
          inner,
          chunk.content_hash,
          {chunk, contribution, [leg]},
          fn {existing, score, found} -> {existing, score + contribution, [leg | found]} end
        )
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(fn {_chunk, score, _legs} -> -score end)
    |> Enum.map(fn {chunk, _score, legs} -> {chunk, Enum.reverse(legs)} end)
  end

  @doc """
  Splits a question into the terms worth matching on.

  Notation survives whole: `@results.parent.state.input` is one term, not five.
  """
  @spec terms(String.t()) :: [String.t()]
  def terms(question) do
    question
    |> String.downcase()
    |> then(&Regex.scan(~r/[@a-z0-9][a-z0-9._\-]*/u, &1))
    |> Enum.map(&List.first/1)
    |> Enum.map(&String.trim(&1, "."))
    |> Enum.reject(&(&1 == "" or String.length(&1) < 2 or MapSet.member?(@stopwords, &1)))
    |> Enum.uniq()
  end

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

  # An identifier is exact: someone typing `@results.parent.state.input` or
  # `resumeContactFlow` means that string. The documents write identifiers in
  # bodies rather than headings, so finding one there says as much as finding
  # an ordinary word in a heading. Rarity alone does not separate the two —
  # "today" appears in as few sections as `resumeContactFlow` does.
  defp body_weight(term, identifiers) do
    if MapSet.member?(identifiers, term), do: @heading_weight, else: 1
  end

  @spec identifiers(String.t()) :: MapSet.t()
  defp identifiers(question) do
    ~r/[@a-zA-Z0-9][a-zA-Z0-9._\-]*/u
    |> Regex.scan(question)
    |> Enum.map(&List.first/1)
    |> Enum.filter(&identifier?/1)
    |> MapSet.new(&(&1 |> String.downcase() |> String.trim(".")))
  end

  # Dotted or @-prefixed notation, or camelCase. Detected before the question
  # is downcased, which is where the camel hump would be lost.
  defp identifier?(token) do
    String.contains?(token, ".") or String.starts_with?(token, "@") or
      Regex.match?(~r/[a-z][A-Z]/, token)
  end

  defp boost(%Chunk{section_path: nil}), do: 0

  defp boost(%Chunk{section_path: path}) do
    if Enum.any?(@boosted_sections, &(path == &1 or String.starts_with?(path, &1 <> "."))),
      do: @boost_ranks,
      else: 0
  end
end
