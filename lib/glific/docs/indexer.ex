defmodule Glific.Docs.Indexer do
  @moduledoc """
  Builds the embedding artifact that `Glific.Docs.Index` reads.

  Idempotent by content hash: a rebuild embeds only the chunks whose text
  changed and drops the ones whose section is gone, so editing a paragraph
  costs one embedding call rather than hundreds.

  Two kinds of section are left out — see `@excluded_sections` and
  `@engineering`.

  Run through `mix glific.docs.index`.
  """

  require Logger

  alias Glific.Docs.{Chunk, Chunker, Index}

  @documents ~w(
    glific_chatbot_knowledge_base
    glific_platform_guide
    glific_operations_manual
    diagnose_playbook
    bigquery_tables
  )

  @source_dir "docs_kb"

  @batch_size 96

  # A table mapping user phrasings to section numbers. It matches almost any
  # question word for word, then answers with "see 3.4" instead of the answer.
  @excluded_sections ["18"]

  # Sections written for Glific's own engineers. An answer built from them
  # tells an NGO to call an internal API it has no credentials for.
  @engineering ~r/lib\/glific\/|\.ex:\d|\bOban\b|\bEcto\b|defmodule|POST \/partner|\bpsql\b|\bJSONB\b/

  @doc "Rebuilds the artifact, embedding only what changed."
  @spec build(keyword()) :: {:ok, map()} | {:error, term()}
  def build(opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    model = Keyword.get(opts, :model, model())
    dimensions = Keyword.get(opts, :dimensions, dimensions())

    chunks = all_chunks()
    known = if force?, do: %{}, else: reusable(model, dimensions)
    {fresh, stale} = Enum.split_with(chunks, &Map.has_key?(known, &1.content_hash))

    case embed_all(stale, model, dimensions) do
      {:ok, embedded} ->
        entries =
          Enum.map(fresh, &%{chunk: &1, vector: Map.fetch!(known, &1.content_hash)}) ++ embedded

        Index.write!(entries,
          model: model,
          dimensions: dimensions,
          chunks: length(entries),
          built_at: DateTime.utc_now()
        )

        {:ok,
         %{
           total: length(entries),
           embedded: length(embedded),
           reused: length(fresh),
           removed: max(map_size(known) - length(fresh), 0),
           model: model,
           dimensions: dimensions
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Every chunk of every document, with the excluded sections removed."
  @spec all_chunks() :: [Chunk.t()]
  def all_chunks do
    @documents
    |> Enum.flat_map(fn document ->
      Application.app_dir(:glific, "priv/#{@source_dir}/#{document}.md")
      |> File.read!()
      |> Chunker.chunk(document)
    end)
    |> Enum.reject(&(excluded?(&1) or engineering?(&1)))
  end

  @doc "Whether a chunk is written for engineers rather than for chatbot staff."
  @spec engineering?(Chunk.t()) :: boolean()
  def engineering?(%Chunk{body: body, heading_path: heading_path}),
    do: String.match?(body, @engineering) or String.match?(heading_path, @engineering)

  @doc "The documents that make up the corpus."
  @spec documents() :: [String.t()]
  def documents, do: @documents

  @doc "The embedding model the artifact is built with."
  @spec model() :: String.t()
  def model, do: config(:embedding_model, "openai:text-embedding-3-small")

  @doc "How many dimensions each stored vector has."
  @spec dimensions() :: pos_integer()
  def dimensions, do: config(:embedding_dimensions, 256)

  @doc "Embeds one piece of text the same way the artifact was built."
  @spec embed(String.t()) :: {:ok, binary()} | {:error, term()}
  def embed(text) do
    case ReqLLM.embed(model(), text, embed_opts()) do
      {:ok, floats} when is_list(floats) -> {:ok, Index.pack(floats)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Glific holds the OpenAI key as OPEN_AI_KEY; req_llm looks for
  # OPENAI_API_KEY. Passed per call so no deployment needs it twice.
  @spec embed_opts(pos_integer() | nil) :: keyword()
  defp embed_opts(dimensions \\ nil) do
    [provider_options: [dimensions: dimensions || dimensions()]]
    |> then(&if(key = api_key(), do: Keyword.put(&1, :api_key, key), else: &1))
  end

  defp api_key do
    case Application.get_env(:glific, :open_ai) do
      key when is_binary(key) and key != "This is not a secret" -> key
      _absent -> nil
    end
  end

  defp excluded?(%Chunk{section_path: nil}), do: false

  defp excluded?(%Chunk{section_path: path, doc_file: "glific_chatbot_knowledge_base"}),
    do: Enum.any?(@excluded_sections, &(path == &1 or String.starts_with?(path, &1 <> ".")))

  defp excluded?(%Chunk{}), do: false

  # Mixing two embedding spaces in one index silently ranks at random.
  defp reusable(model, dimensions) do
    metadata = Index.metadata()

    if metadata[:model] == model and metadata[:dimensions] == dimensions do
      Map.new(Index.entries(), &{&1.chunk.content_hash, &1.vector})
    else
      %{}
    end
  end

  defp embed_all([], _model, _dimensions), do: {:ok, []}

  defp embed_all(chunks, model, dimensions) do
    chunks
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case embed_batch(batch, model, dimensions) do
        {:ok, entries} -> {:cont, {:ok, acc ++ entries}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp embed_batch(batch, model, dimensions) do
    texts = Enum.map(batch, &Chunk.embed_text/1)

    case ReqLLM.embed(model, texts, embed_opts(dimensions)) do
      {:ok, vectors} when length(vectors) == length(batch) ->
        {:ok,
         batch
         |> Enum.zip(vectors)
         |> Enum.map(fn {chunk, floats} -> %{chunk: chunk, vector: Index.pack(floats)} end)}

      {:ok, vectors} ->
        {:error, "expected #{length(batch)} embeddings, got #{length(vectors)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config(key, default),
    do: :glific |> Application.get_env(Glific.Docs, []) |> Keyword.get(key, default)
end
