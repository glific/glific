defmodule Glific.Submissions do
  @moduledoc """
  The Submissions context
  """

  alias Glific.{
    Repo,
    Submissions.Submission,
  }

  @doc """
  Creates a organization.

  ## Examples

      iex> Glific.Submissions.create_submission(%{name: value})
      {:ok, %Glific.Organization{}}

      iex> Glific.Submissions.create_submission(%{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_submission(map()) :: {:ok, Submission.t()} | {:error, Ecto.Changeset.t()}
  def create_submission(attrs \\ %{}) do
    %Submission{}
    |> Submission.changeset(attrs)
    |> Repo.insert(skip_organization_id: true)
  end
end
