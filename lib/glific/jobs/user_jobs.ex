defmodule Glific.Jobs.UserJob do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  @required_fields [
    :status,
    :type,
    :total_tasks,
    :tasks_done,
    :organization_id,
    :all_tasks_created
  ]
  @optional_fields [:errors]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          status: String.t() | nil,
          type: String.t() | nil,
          total_tasks: non_neg_integer | nil,
          tasks_done: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          errors: map() | nil,
          all_tasks_created: boolean | false,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "user_jobs" do
    field(:status, :string, default: "pending")
    field(:type, :string)
    field(:total_tasks, :integer)
    field(:tasks_done, :integer)
    field(:errors, :map, default: %{})
    field(:all_tasks_created, :boolean, default: false)

    belongs_to(:organization, Organization, foreign_key: :organization_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(UserJob.t(), map()) :: Ecto.Changeset.t()
  def changeset(user_job, attrs) do
    user_job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Creates a new user job
  """
  @spec create_user_job(map()) :: UserJob.t()
  def create_user_job(attrs) do
    %UserJob{}
    |> changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Updates a user job with the given changeset.
  """
  @spec update_user_job(UserJob.t(), map()) :: {:ok, UserJob.t()} | {:error, Ecto.Changeset.t()}
  def update_user_job(user_job, changes) do
    user_job
    |> changeset(changes)
    |> Repo.update()
  end

  @doc """
  Fetch user jobs wrto the filters and arguments
  """
  @spec list_user_jobs(map()) :: [UserJob.t()]
  def list_user_jobs(args \\ %{}) do
    args
    |> Repo.list_filter_query(UserJob, &Repo.opts_with_name/2, &filter_with/2)
    |> Repo.all()
  end

  @spec filter_with(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from(u in query, where: u.status == ^status)

      {:all_tasks_created, all_tasks_created}, query ->
        from(u in query, where: u.all_tasks_created == ^all_tasks_created)

      {:organization_id, organization_id}, query ->
        from(u in query, where: u.organization_id == ^organization_id)

      {:id, id}, query ->
        from(u in query, where: u.id == ^id)

      _, query ->
        query
    end)
  end
end
