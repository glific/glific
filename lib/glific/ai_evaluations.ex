defmodule Glific.AIEvaluations do
  @moduledoc """
  Context module for AI Evaluations stored in the database.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    AIEvaluations.AIEvaluation,
    Repo
  }

  @doc """
  Returns the list of AI evaluations for an organization.

  ## Examples

      iex> list_ai_evaluations(%{organization_id: 1})
      [%AIEvaluation{}, ...]

  """
  @spec list_ai_evaluations(map()) :: [AIEvaluation.t()]
  def list_ai_evaluations(args) do
    args
    |> Repo.list_filter_query(AIEvaluation, &Repo.opts_with_inserted_at/2, &filter_with/2)
    |> Repo.all()
  end

  @doc """
  Returns the count of AI evaluations for an organization.
  """
  @spec count_ai_evaluations(map()) :: non_neg_integer()
  def count_ai_evaluations(args) do
    args
    |> Repo.list_filter_query(AIEvaluation, &Repo.opts_with_inserted_at/2, &filter_with/2)
    |> Repo.aggregate(:count)
  end

  @spec filter_with(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        where(query, [e], e.status == ^status)

      {:name, name}, query ->
        where(query, [e], ilike(e.name, ^"%#{name}%"))

      _, query ->
        query
    end)
  end
end
