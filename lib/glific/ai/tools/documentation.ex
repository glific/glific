defmodule Glific.AI.Tools.Documentation do
  @moduledoc """
  Glific's own documentation, searched and returned for the model to answer from.

  The other tools read an organisation's data; this one reads how Glific works,
  which most support questions also turn on — not "what is this contact's
  status" but "what does that status mean".

  It returns sections rather than an answer, leaving the reply to the skill.
  Retrieval is `Glific.Docs.Search`, which is in memory and takes no database
  connection.
  """

  alias Glific.Docs.{Chunk, Search}

  @behaviour Glific.AI.Tool

  @doc "The documentation search this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "search_documentation",
        description: """
        Searches Glific's documentation and returns the sections that answer a
        question: how a feature works, what a setting does, what a limit is,
        what an error means, and the exact syntax for flow variables, webhooks
        and templates.

        Use it whenever a question is about how Glific works rather than about
        this organisation's own data — and use it alongside the data tools when
        a question is both, which support questions usually are. Search with
        the words the person used; the index handles their phrasing.

        Each section carries the page it came from, so an answer can link it.
        """,
        parameters: [
          query: [
            type: :string,
            required: true,
            doc: "What to look up, in the words the person asked it"
          ],
          limit: [type: :pos_integer, default: 5, doc: "How many sections to return, at most 10"]
        ]
      }
    ]
  end

  @doc "The index is in memory, so this needs no database connection."
  @impl Glific.AI.Tool
  @spec reads_database?() :: boolean()
  def reads_database?, do: false

  @doc "Searches the documentation and returns the matching sections."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("search_documentation", %{query: query} = args) do
    case Search.find(query, limit: min(args[:limit], 10)) do
      [] -> {:error, no_match(query)}
      results -> {:ok, Enum.map(results, &section(&1.chunk))}
    end
  end

  defp section(%Chunk{} = chunk) do
    %{
      title: Chunk.title(chunk),
      section: chunk.heading_path,
      body: chunk.body,
      source: chunk.source_url
    }
  end

  defp no_match(query),
    do: """
    Nothing in the documentation matches "#{query}". Try the words the person \
    used rather than Glific's internal names, or answer from what you know \
    without citing a source.\
    """
end
