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

  An unchanged file is left alone so its chunks keep their hashes and the next
  index reuses their embeddings.
  """
  @spec run() :: {:ok, %{changed: [String.t()], unchanged: [String.t()]}} | {:error, term()}
  def run do
    Indexer.documents()
    |> Enum.reduce_while({[], []}, fn document, {changed, unchanged} ->
      case fetch(document) do
        {:ok, :changed} -> {:cont, {[document | changed], unchanged}}
        {:ok, :unchanged} -> {:cont, {changed, [document | unchanged]}}
        {:error, reason} -> {:halt, {:error, document, reason}}
      end
    end)
    |> case do
      {:error, document, reason} -> {:error, "#{document}: #{SafeLog.safe_inspect(reason)}"}
      {changed, unchanged} -> {:ok, %{changed: changed, unchanged: unchanged}}
    end
  end

  @doc "Where a document is read from."
  @spec url(String.t()) :: String.t()
  def url(document),
    do: "https://raw.githubusercontent.com/#{@repository}/#{@branch}/#{document}.md"

  defp fetch(document) do
    case Req.get(url(document), retry: :transient, max_retries: 2) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> write(document, body)
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(document, body) do
    path = Path.join([File.cwd!(), "priv", "docs_kb", "#{document}.md"])

    if File.exists?(path) and File.read!(path) == body do
      {:ok, :unchanged}
    else
      File.write!(path, body)
      {:ok, :changed}
    end
  end
end
