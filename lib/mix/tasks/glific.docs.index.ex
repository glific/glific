defmodule Mix.Tasks.Glific.Docs.Index do
  @shortdoc "Embeds the shipped documentation into priv/glific_ai/embeddings.etf"

  @moduledoc """
  Rebuilds the documentation embedding artifact.

  Only chunks whose text changed are re-embedded. Commit the artifact it
  writes — boot reads it rather than rebuilding.

  `--sync` pulls the latest documentation from `glific/dify` first.

      mix glific.docs.index
      mix glific.docs.index --sync
      mix glific.docs.index --force
      mix glific.docs.index --model openai:text-embedding-3-large --dimensions 512

  Needs the embedding provider's key in the environment.
  """

  use Mix.Task

  alias Glific.Docs.{Index, Indexer, Sync}
  alias Glific.SafeLog

  @switches [force: :boolean, model: :string, dimensions: :integer, sync: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:req_llm)

    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)

    if opts[:sync], do: sync()

    Mix.shell().info("Chunking #{length(Indexer.all_chunks())} sections…")

    case Indexer.build(opts) do
      {:ok, summary} -> report(summary)
      {:error, reason} -> Mix.raise("Indexing failed: #{SafeLog.safe_inspect(reason)}")
    end
  end

  defp sync do
    {:ok, _apps} = Application.ensure_all_started(:req)

    case Sync.run() do
      {:ok, %{changed: [], unchanged: unchanged}} ->
        Mix.shell().info("Synced #{length(unchanged)} documents from glific/dify, none changed.")

      {:ok, %{changed: changed}} ->
        Mix.shell().info("Synced from glific/dify, updated: #{Enum.join(changed, ", ")}")

      {:error, reason} ->
        Mix.raise("Sync failed: #{reason}")
    end
  end

  defp report(summary) do
    Mix.shell().info("""

    Indexed #{summary.total} chunks with #{summary.model} at #{summary.dimensions} dimensions.
      embedded  #{summary.embedded}
      reused    #{summary.reused}
      removed   #{summary.removed}

    Wrote #{Index.artifact_path()}
    """)
  end
end
