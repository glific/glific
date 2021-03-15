defmodule Glific.Triggers.Trigger do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  import Ecto.Query, warn: false

  alias Glific.{
    Flows.Flow,
    Groups.Group,
    Partners,
    Partners.Organization,
    Repo
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          trigger_type: String.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          group_id: non_neg_integer | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil,
          start_at: DateTime.t() | nil,
          end_date: Date.t() | nil,
          last_trigger_at: DateTime.t() | nil,
          next_trigger_at: DateTime.t() | nil,
          is_repeating: boolean(),
          frequency: list() | nil,
          days: list() | nil,
          is_active: boolean(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :organization_id,
    :flow_id,
    :start_at
  ]
  @optional_fields [
    :name,
    :is_active,
    :trigger_type,
    :group_id,
    :end_date,
    :last_trigger_at,
    :next_trigger_at,
    :is_repeating,
    :frequency,
    :days
  ]

  schema "triggers" do
    field :trigger_type, :string, default: "scheduled"

    belongs_to :group, Group
    belongs_to :flow, Flow

    field :start_at, :utc_datetime
    field :end_date, :date
    field :name, :string

    field :last_trigger_at, :utc_datetime
    field :next_trigger_at, :utc_datetime

    field :frequency, {:array, :string}, default: []
    field :days, {:array, :integer}, default: []

    field :is_active, :boolean, default: true
    field :is_repeating, :boolean, default: false

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Trigger.t(), map()) :: Ecto.Changeset.t()
  def changeset(trigger, attrs) do
    trigger
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:organization_id)
  end

  @spec start_at(map()) :: DateTime.t()
  defp start_at(%{start_at: nil} = attrs) do
    {:ok, ndt} = NaiveDateTime.new(attrs.start_date, attrs.start_time)
    tz = Partners.organization_timezone(attrs.organization_id)
    dt = DateTime.from_naive!(ndt, tz)
    DateTime.shift_zone!(dt, "Etc/UTC")
  end

  ## We might need to change this and convert the datetime to utc
  defp start_at(%{start_at: start_at} = _attrs),
    do: start_at

  @spec get_name(map()) :: String.t()
  defp get_name(%{name: name} = _attrs) when not is_nil(name), do: name

  defp get_name(attrs) do
    with {:ok, flow} <-
           Repo.fetch_by(Flow, %{id: attrs.flow_id, organization_id: attrs.organization_id}),
         {:ok, ndt} <- NaiveDateTime.new(attrs.start_date, attrs.start_time),
         {:ok, date} <- Timex.format(ndt, "_{D}/{M}/{YYYY}_{h12}:{0m}{AM}") do
      "#{flow.name}#{date}"
    end
  end

  @spec fix_attrs(map()) :: map()
  defp fix_attrs(attrs) do
    # compute start_at if not set
    start_at = start_at(attrs)

    attrs
    |> Map.put(:start_at, start_at)
    |> Map.put(:name, get_name(attrs))
    # set the initial value of the next firing of the trigger
    |> Map.put(:next_trigger_at, start_at)
  end

  @doc false
  @spec create_trigger(map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger(attrs) do
    %Trigger{}
    |> Trigger.changeset(attrs |> Map.put_new(:start_at, nil) |> fix_attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the triggger
  """
  @spec update_trigger(Trigger.t(), map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger(%Trigger{} = trigger, attrs) do
    trigger
    |> Trigger.changeset(attrs |> Map.put_new(:start_at, nil) |> fix_attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of triggers filtered by args
  """
  @spec list_triggers(map()) :: [Trigger.t()]
  def list_triggers(args) do
    Repo.list_filter(args, Trigger, &Repo.opts_with_name/2, &filter_with/2)
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:flow, flow}, query ->
        from q in query,
          join: c in assoc(q, :flow),
          where: ilike(c.name, ^"%#{flow}%")

      {:group, group}, query ->
        from q in query,
          join: g in assoc(q, :group),
          where: ilike(g.label, ^"%#{group}%")

      _, query ->
        query
    end)
  end

  @doc false
  @spec delete_trigger(Trigger.t()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def delete_trigger(%Trigger{} = trigger) do
    trigger
    |> Trigger.changeset(%{})
    |> Repo.delete()
  end

  @doc """
  Return the count of triggers, using the same filter as list_triggers
  """
  @spec count_triggers(map()) :: integer
  def count_triggers(args),
    do: Repo.count_filter(args, Trigger, &Repo.filter_with/2)
end
