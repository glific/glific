defmodule Glific.Saas.ConsultingHour do
  @moduledoc """
  The table structure to record consulting hours
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  # define all the required fields for
  @required_fields [
    :organization_id,
    :participants,
    :staff,
    :when,
    :duration,
    :content
  ]

  # define all the optional fields for organization
  @optional_fields [
    :organization_name,
    :is_billable
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_name: String.t() | nil,
          participants: String.t() | nil,
          staff: String.t() | nil,
          when: DateTime.t() | nil,
          duration: non_neg_integer | nil,
          is_billable: boolean() | true,
          content: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "consulting_hours" do
    field :organization_name, :string
    field :participants, :string
    field :staff, :string

    field :when, :utc_datetime
    field :duration, :integer
    field :content, :string

    field :is_billable, :boolean, default: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ConsultingHour.t(), map()) :: Ecto.Changeset.t()
  def changeset(consulting_hour, attrs) do
    consulting_hour
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:when, :staff, :organization_id],
      message: "Sorry, Consulting hours are already filled for this call"
    )
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Create a consulting_hour record
  """
  @spec create_consulting_hour(map()) :: {:ok, ConsultingHour.t()} | {:error, Ecto.Changeset.t()}
  def create_consulting_hour(attrs) do
    %ConsultingHour{}
    |> changeset(Map.put(attrs, :organization_id, attrs.organization_id))
    |> Repo.insert()
  end

  @doc """
  Retrieve a consulting_hour record by clauses
  """
  @spec get_consulting_hour(map()) :: ConsultingHour.t() | nil
  def get_consulting_hour(clauses),
    do: Repo.get_by(ConsultingHour, clauses, skip_organization_id: true)

  @doc """
  Returns the list of consulting hours.

  ## Examples

      iex> list_consulting_hours()
      [%ConsultingHour{}, ...]

  """
  @spec list_consulting_hours(map()) :: [ConsultingHour.t()]
  def list_consulting_hours(args),
    do:
      Repo.list_filter(args, ConsultingHour, &Repo.opts_with_inserted_at/2, &filter_with/2,
        skip_organization_id: true
      )

  @doc """
  Return the count of consulting hours, using the same filter as list_consulting_hours
  """
  @spec count_consulting_hours(map()) :: integer
  def count_consulting_hours(args),
    do: Repo.count_filter(args, ConsultingHour, &filter_with/2, skip_organization_id: true)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to consulting hours only.
    Enum.reduce(filter, query, fn
      {:organization_name, organization_name}, query ->
        from q in query, where: ilike(q.organization_name, ^"%#{organization_name}%")

      {:staff, staff}, query ->
        from q in query, where: ilike(q.staff, ^"%#{staff}%")

      {:is_billable, is_billable}, query ->
        from q in query, where: q.is_billable == ^is_billable

      {:participants, participants}, query ->
        from q in query, where: ilike(q.participants, ^"%#{participants}%")

      _, query ->
        query
    end)
  end

  @doc """
  Update the consulting_hour record
  """
  @spec update_consulting_hour(ConsultingHour.t(), map()) ::
          {:ok, ConsultingHour.t()} | {:error, Ecto.Changeset.t()}
  def update_consulting_hour(%ConsultingHour{} = consulting_hour, attrs) do
    consulting_hour
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete the consulting_hour record
  """
  @spec delete_consulting_hour(ConsultingHour.t()) ::
          {:ok, ConsultingHour.t()} | {:error, Ecto.Changeset.t()}
  def delete_consulting_hour(%ConsultingHour{} = consulting_hour) do
    Repo.delete(consulting_hour, skip_organization_id: true)
  end
end
