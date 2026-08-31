defmodule Glific.AI.Tools.Assistants do
  @moduledoc """
  Reads about the organisation's AI assistants — the ones staff configure to
  answer beneficiaries, not Glific AI itself — and the evaluations that score
  them.

  An assistant's behaviour comes from its active config version, so the version
  is what a question about "why did it answer that" actually needs. Evaluations
  live here too: they exist only to score an assistant against a golden
  question-and-answer set, so they are part of the same lifecycle.
  """

  import Ecto.Query

  alias Glific.{AIEvaluations, Assistants.Assistant, Repo}

  @behaviour Glific.AI.Tool

  @fields [
    :id,
    :name,
    :description,
    :assistant_display_id,
    :clone_status,
    :active_config_version_id,
    :inserted_at
  ]

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "list_assistants",
        description: """
        Lists this organisation's AI assistants with their names and ids. Call
        this first when a question names an assistant, to find its id.
        """,
        parameters: [
          name: [type: :string, doc: "Only assistants whose name contains this text"],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "get_assistant",
        description: """
        Describes one assistant, including its active configuration version.
        Use this to explain how an assistant is set up or why it answers the way
        it does.
        """,
        parameters: [
          assistant_id: [
            type: :pos_integer,
            required: true,
            doc: "The assistant's id, from list_assistants"
          ]
        ]
      },
      %{
        name: "list_evaluations",
        description: """
        Lists evaluation runs for this organisation's assistants, with their
        status and scores. Use this to answer whether a change to an assistant
        made it better or worse.
        """,
        parameters: [
          status: [type: :string, doc: ~s(Only runs with this status, e.g. "completed")],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_golden_qas",
        description: """
        Lists the golden question-and-answer datasets an evaluation runs against,
        with how many items each holds.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  # Queried directly rather than through `Assistants.list_assistants/1`: that
  # builds a legacy shape which raises on an assistant with no active config
  # version, which is the normal state of a newly created one.
  @impl Glific.AI.Tool
  def run("list_assistants", args) do
    assistants =
      Assistant
      |> maybe_named(args[:name])
      |> order_by([a], desc: a.inserted_at)
      |> limit(^min(args[:limit], 100))
      |> select([a], ^@fields)
      |> Repo.all()

    {:ok, assistants}
  end

  def run("get_assistant", %{assistant_id: id}) do
    Assistant
    |> where([a], a.id == ^id)
    |> select([a], ^@fields)
    |> Repo.one()
    |> case do
      nil -> {:error, "No assistant with id #{id} exists in this organisation."}
      assistant -> {:ok, assistant}
    end
  end

  def run("list_evaluations", args) do
    filter = if args[:status], do: %{status: args[:status]}, else: %{}

    evaluations =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}}
      |> AIEvaluations.list_ai_evaluations()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          status: &1.status,
          failure_reason: &1.failure_reason,
          results: &1.results,
          golden_qa_id: &1.golden_qa_id,
          assistant_config_version_id: &1.assistant_config_version_id,
          inserted_at: &1.inserted_at
        }
      )

    {:ok, evaluations}
  end

  def run("list_golden_qas", args) do
    datasets =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}}
      |> AIEvaluations.list_golden_qas()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          file_name: &1.file_name,
          total_items: &1.total_items,
          inserted_at: &1.inserted_at
        }
      )

    {:ok, datasets}
  end

  @spec maybe_named(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_named(query, nil), do: query
  defp maybe_named(query, name), do: where(query, [a], ilike(a.name, ^"%#{name}%"))
end
