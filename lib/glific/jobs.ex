defmodule Glific.Jobs do
  @moduledoc """
  The Jobs context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Repo,
    Jobs.ChatbaseJob
  }

  @doc """
  Gets a single job entry for the organization.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_chatbase_job!(integer) :: User.t()
  def get_chatbase_job!(organization_id),
    do: Repo.get_by!(
          ChatbaseJob,
          %{organization_id: organization_id)
        )

  @doc """
  Create or update a chatbase_job with the message_id and
  organization_id
  """
  @spec upsert_chatbase_job(map()) :: {:ok, ChatbaseJob.t()} | {:error, Ecto.Changeset.t()}
  def upsert_chatbase_job(attrs) do
    changeset = ChatbaseJob.changeset(%ChatbaseJob{}, attrs)

    chatbase_job =
      Repo.insert!(
        changeset,
        returning: true,
        on_conflict: [set: [message_id: attrs.message_id]]
        conflict_target: :organization_id
      )
  end
end
