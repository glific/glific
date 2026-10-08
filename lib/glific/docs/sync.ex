defmodule Glific.Docs.Sync do
  @moduledoc """
  Copies the documentation from `glific/dify`, where it is written and reviewed,
  into `priv/docs_kb`.

  Run through `mix glific.docs.index --sync`, so what a release ships is a
  committed file rather than whatever the network returned that morning.
  """

  require Logger

  alias Glific.Docs.Indexer
  alias Glific.SafeLog

  @repository "glific/dify"
  @branch "main"

  @doc """
  Downloads every document, returning which ones changed.

  Nothing is written until every document has arrived, so a failure halfway
  through cannot leave the corpus half from one revision and half from another.
  An unchanged file is left alone, so its chunks keep their hashes and the next
  index reuses their embeddings.
  """
  @spec run() :: {:ok, %{changed: [String.t()], unchanged: [String.t()]}} | {:error, term()}
  def run do
    with {:ok, fetched} <- fetch_all(Indexer.documents()) do
      {:ok, Enum.reduce(fetched, %{changed: [], unchanged: []}, &write/2)}
    end
  end

  # A test supplies a plug here rather than reaching GitHub.
  defp request_options do
    Keyword.merge(
      [retry: :transient, max_retries: 2],
      Application.get_env(:glific, :docs_sync_request_options, [])
    )
  end

  @spec fetch_all([String.t()]) :: {:ok, [{String.t(), String.t()}]} | {:error, String.t()}
  defp fetch_all(documents) do
    Enum.reduce_while(documents, {:ok, []}, fn document, {:ok, acc} ->
      case fetch(document) do
        {:ok, body} ->
          {:cont, {:ok, [{document, body} | acc]}}

        {:error, reason} ->
          {:halt, {:error, "#{document}: #{SafeLog.safe_inspect(reason)}"}}
      end
    end)
  end

  @doc "Where a document is read from."
  @spec url(String.t()) :: String.t()
  def url(document),
    do: "https://raw.githubusercontent.com/#{@repository}/#{@branch}/#{document}.md"

  defp fetch(document) do
    case Req.get(url(document), request_options()) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write({document, body}, acc) do
    path = Path.join([File.cwd!(), "priv", "docs_kb", "#{document}.md"])

    if File.exists?(path) and File.read!(path) == body do
      Map.update!(acc, :unchanged, &[document | &1])
    else
      File.write!(path, body)
      Map.update!(acc, :changed, &[document | &1])
    end
  end
end
