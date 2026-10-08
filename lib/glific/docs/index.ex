defmodule Glific.Docs.Index do
  @moduledoc """
  The chunked documentation and its embeddings, held in `:persistent_term`.

  A few hundred sections that change only when someone edits a markdown file,
  so they are read once from a build artifact and every process reads them
  without copying.

  Vectors are stored normalised as little-endian float32, which makes cosine
  similarity a plain dot product.

  `mix glific.docs.index` writes the artifact, so boot needs no embedding
  provider. Without it the documents are chunked at boot and carry no vectors,
  which leaves the lexical leg of a search working and the semantic leg silent.
  """

  require Logger

  alias Glific.Docs.{Chunk, Indexer}

  @index_key {__MODULE__, :entries}
  @artifact "docs_kb/embeddings.etf"

  @typedoc "A chunk and its vector. `vector` is nil when no artifact was built."
  @type entry() :: %{chunk: Chunk.t(), vector: binary() | nil}

  @doc "Reads the artifact into `:persistent_term`. Called once on boot."
  @spec warm() :: :ok
  def warm do
    :persistent_term.put(@index_key, read_artifact())
    :ok
  end

  @doc "Every indexed chunk with its vector."
  @spec entries() :: [entry()]
  def entries, do: :persistent_term.get(@index_key, nil) || read_artifact()

  @doc "Every indexed chunk, without its vector."
  @spec chunks() :: [Chunk.t()]
  def chunks, do: Enum.map(entries(), & &1.chunk)

  @doc "How many chunks are indexed."
  @spec count() :: non_neg_integer()
  def count, do: length(entries())

  @doc "Where the build artifact lives."
  @spec artifact_path() :: String.t()
  def artifact_path, do: Application.app_dir(:glific, "priv/#{@artifact}")

  @doc "Writes entries to the artifact, replacing whatever was there."
  @spec write!([entry()], keyword()) :: :ok
  def write!(entries, metadata) do
    payload = %{version: 1, metadata: Map.new(metadata), entries: entries}
    File.write!(source_path(), :erlang.term_to_binary(payload, compressed: 6))
    :ok
  end

  @doc "What the last build recorded about itself: model, dimensions, when."
  @spec metadata() :: map()
  def metadata do
    case File.read(artifact_path()) do
      {:ok, binary} -> binary |> :erlang.binary_to_term() |> Map.get(:metadata, %{})
      {:error, _reason} -> %{}
    end
  end

  @doc "Normalises a vector of floats into the stored binary form."
  @spec pack([float()]) :: binary()
  def pack(floats) do
    magnitude = floats |> Enum.reduce(0.0, &(&2 + &1 * &1)) |> :math.sqrt()
    divisor = if magnitude == 0.0, do: 1.0, else: magnitude

    for value <- floats, into: <<>>, do: <<value / divisor::float-32-little>>
  end

  @doc """
  Cosine similarity of two packed vectors.

  Returns `0.0` for vectors of different widths: they come from different
  embedding models, and scoring the overlap would rank them at random.
  """
  @spec similarity(binary(), binary()) :: float()
  def similarity(left, right) when byte_size(left) == byte_size(right),
    do: dot(left, right, 0.0)

  def similarity(_left, _right), do: 0.0

  defp dot(<<>>, _right, acc), do: acc

  defp dot(<<a::float-32-little, left::binary>>, <<b::float-32-little, right::binary>>, acc),
    do: dot(left, right, acc + a * b)

  # Reads resolve to the build directory; the task writes to the source tree.
  defp source_path, do: Path.join([File.cwd!(), "priv", @artifact])

  # Not `:safe`: it rejects the compressed struct payload, and this artifact
  # ships inside the release.
  defp read_artifact do
    case File.read(artifact_path()) do
      {:ok, binary} ->
        binary |> :erlang.binary_to_term() |> Map.fetch!(:entries)

      {:error, reason} ->
        Logger.info("docs index not built (#{reason}); semantic search is disabled")
        unembedded()
    end
  end

  # Chunking the markdown costs a few hundred milliseconds and no network, so a
  # deployment that never ran the task still answers from the lexical leg.
  defp unembedded do
    Enum.map(Indexer.all_chunks(), &%{chunk: &1, vector: nil})
  rescue
    exception ->
      Logger.warning("docs could not be chunked: #{Exception.message(exception)}")
      []
  end
end
