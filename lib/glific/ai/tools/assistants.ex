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

  alias Glific.{AIEvaluations, Assistants, Assistants.Assistant, Repo}

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
        Describes one assistant. Add `include: ["config"]` for the active
        configuration version — the instructions and model actually behind its
        answers, which is what a question about why it replied a certain way
        needs.
        """,
        parameters: [
          assistant_id: [
            type: :pos_integer,
            required: true,
            doc: "The assistant's id, from list_assistants"
          ],
          include: [
            type: {:list, {:in, ["config"]}},
            default: [],
            doc: ~s(Add "config" for the active configuration version behind its answers)
          ]
        ]
      },
      %{
        name: "list_evaluations",
        description: """
        Lists evaluation runs for this organisation's assistants, with their
        status and scores. Use this to answer whether a change to an assistant
        made it better or worse.

        Add `include: ["datasets"]` for the golden question-and-answer sets the
        runs score against, and how many items each holds.
        """,
        parameters: [
          status: [type: :string, doc: ~s(Only runs with this status, e.g. "completed")],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"],
          include: [
            type: {:list, {:in, ["datasets"]}},
            default: [],
            doc: ~s(Add "datasets" for the golden question-and-answer sets runs score against)
          ]
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

  def run("get_assistant", %{assistant_id: id} = args) do
    Assistant
    |> where([a], a.id == ^id)
    |> select([a], ^@fields)
    |> Repo.one()
    |> case do
      nil -> {:error, "No assistant with id #{id} exists in this organisation."}
      assistant -> {:ok, with_config(assistant, args[:include])}
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

    {:ok, with_datasets(evaluations, args[:include])}
  end

  @spec with_config(map(), [String.t()]) :: map()
  defp with_config(assistant, include) do
    if "config" in include,
      do: Map.put(assistant, :config, config_version(assistant.active_config_version_id)),
      else: assistant
  end

  @spec config_version(non_neg_integer() | nil) :: map() | nil
  defp config_version(nil), do: nil

  defp config_version(id) do
    Assistants.list_assistant_config_versions()
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> nil
      version -> Map.take(version, [:id, :version, :status, :inserted_at])
    end
  end

  @spec with_datasets([map()], [String.t()]) :: [map()] | map()
  defp with_datasets(evaluations, include) do
    if "datasets" in include,
      do: %{evaluations: evaluations, datasets: datasets()},
      else: evaluations
  end

  @spec datasets() :: [map()]
  defp datasets do
    %{filter: %{}, opts: %{limit: 100, offset: 0, order: :desc}}
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
  end

  @spec maybe_named(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_named(query, nil), do: query
  defp maybe_named(query, name), do: where(query, [a], ilike(a.name, ^"%#{name}%"))
end
