defmodule Mix.Tasks.Glific.Docs.Index do
  @shortdoc "Embeds the shipped documentation into priv/docs_kb/embeddings.etf"

  @moduledoc """
  Rebuilds the documentation embedding artifact.

  Only sections whose text changed are re-embedded, so editing a paragraph
  costs one request rather than hundreds. Commit the artifact it writes — boot
  reads it rather than rebuilding, so starting Glific needs no provider.

      mix glific.docs.index
      mix glific.docs.index --force
      mix glific.docs.index --model openai:text-embedding-3-large --dimensions 512

  Needs the embedding provider's key in the environment.
  """

  use Mix.Task

  alias Glific.Docs

  @switches [force: :boolean, model: :string, dimensions: :integer]

  # One request per batch, well inside the provider's input cap.
  @batch_size 96

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:req_llm)

    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    model = Keyword.get(opts, :model, Docs.model())
    dimensions = Keyword.get(opts, :dimensions, Docs.dimensions())

    chunks = Docs.all_chunks()
    Mix.shell().info("Chunking #{length(chunks)} sections…")

    known = if opts[:force], do: %{}, else: reusable(model, dimensions)
    {fresh, stale} = Enum.split_with(chunks, &Map.has_key?(known, &1.hash))

    case embed_all(stale, model, dimensions) do
      {:ok, embedded} ->
        entries = Enum.map(fresh, &%{chunk: &1, vector: Map.fetch!(known, &1.hash)}) ++ embedded

        Docs.write!(entries,
          model: model,
          dimensions: dimensions,
          chunks: length(entries),
          built_at: DateTime.utc_now()
        )

        report(entries, embedded, fresh, known, model, dimensions)

      {:error, reason} ->
        Mix.raise("Indexing failed: #{Glific.SafeLog.safe_inspect(reason)}")
    end

    :ok
  end

  # Mixing two embedding spaces in one index silently ranks at random.
  defp reusable(model, dimensions) do
    metadata = Docs.metadata()

    if metadata[:model] == model and metadata[:dimensions] == dimensions,
      do: Map.new(Docs.entries(), &{&1.chunk.hash, &1.vector}),
      else: %{}
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
    texts = Enum.map(batch, &"#{&1.heading_path}\n\n#{&1.body}")

    case ReqLLM.embed(model, texts, Docs.embed_opts(dimensions)) do
      {:ok, vectors} when length(vectors) == length(batch) ->
        {:ok,
         batch
         |> Enum.zip(vectors)
         |> Enum.map(fn {chunk, floats} -> %{chunk: chunk, vector: Docs.pack(floats)} end)}

      {:ok, vectors} ->
        {:error, "expected #{length(batch)} embeddings, got #{length(vectors)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp report(entries, embedded, fresh, known, model, dimensions) do
    Mix.shell().info("""

    Indexed #{length(entries)} sections with #{model} at #{dimensions} dimensions.
      embedded  #{length(embedded)}
      reused    #{length(fresh)}
      removed   #{max(map_size(known) - length(fresh), 0)}

    Wrote #{Docs.artifact_path()}
    """)
  end
end
