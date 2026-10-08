defmodule Glific.AI.Tools.Documentation do
  @moduledoc """
  Glific's own documentation: how the product works, what its screens do, and
  what its concepts mean.

  Every other tool module reads an organisation's data. This one reads the
  documentation instead, so a question about how Glific works is answered from
  what is written rather than from what the model happens to remember.

  The vocabulary a search needs is on the tool rather than in the prompt of a
  skill that holds it: a question rarely separates how the product works from
  what an organisation's data says, so more than one skill ends up with this
  tool and each would otherwise repeat the same guidance.
  """

  alias Glific.AI.Documentation

  @behaviour Glific.AI.Tool

  @doc "Reads the bundled documentation, never the organisation's data."
  @impl Glific.AI.Tool
  @spec reads_database?() :: boolean()
  def reads_database?, do: false

  @doc """
  The documentation lookup this module offers.
  """
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "search_documentation",
        description: """
        Searches Glific's product documentation and returns the sections that
        match, with the page each came from.

        Search a short phrase of Glific's own terms — three to six words rank
        best. Do not pass the person's message through: a pasted support message
        ranks far worse than the same question translated, and one with no
        Glific term in it at all comes back empty.

        The documentation only uses Glific's vocabulary and the people asking do
        not, so translate first:

          * a programme, a campaign, an intervention → a flow
          * a group, an area, a district, a cohort, a batch → a collection
          * their details, their information, what we know about them → contact
            fields, `@contact.fields.<name>`
          * an answer someone gave, a saved value, a variable → a flow result,
            `@results.<name>`
          * a scheduled message, an automatic message, a reminder → a trigger
          * a message we start, a message outside the chat → an HSM template,
            and the 24-hour session window
          * asking someone something and keeping the reply → a Wait for Response
            node, then a flow result

        The documentation also covers the services Glific connects to —
        BigQuery exports, Looker Studio dashboards, cloud storage buckets,
        template approval at Meta, a messaging provider's own account — so
        search before deciding a question is about another product.

        Search again with different wording when the sections that come back do
        not answer the question. Two or three searches cost almost nothing.
        """,
        parameters: [
          query: [
            type: :string,
            required: true,
            doc: "What to look for, in Glific's own terms"
          ],
          limit: [
            type: :pos_integer,
            default: 5,
            doc: "How many sections to return, at most 10"
          ]
        ]
      }
    ]
  end

  @doc """
  Answers the documentation lookup.
  """
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("search_documentation", %{query: query} = args) do
    case Documentation.search(query, min(args[:limit], 10)) do
      [] ->
        {:error,
         "Nothing in the documentation matches that. Try Glific's own terms for it, " <>
           "or a narrower phrase."}

      sections ->
        {:ok, sections}
    end
  end
end
