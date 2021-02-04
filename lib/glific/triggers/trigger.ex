defmodule Glific.Triggers.Trigger do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
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
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
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
    :name,
    :organization_id,
    :flow_id,
    :start_at
  ]
  @optional_fields [
    :trigger_type,
    :contact_id,
    :group_id,
    :end_at,
    :last_trigger_at,
    :next_trigger_at,
    :is_repeating,
    :frequency,
    :days
  ]

  schema "triggers" do
    field :name, :string

    field :trigger_type, :string, default: "scheduled"

    belongs_to :contact, Contact
    belongs_to :group, Group
    belongs_to :flow, Flow

    field :start_at, :utc_datetime
    field :end_date, :date

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

  @spec start_at(map(), non_neg_integer) :: DateTime.t()
  defp start_at(%{start_at: nil} = attrs, org_id) do
    {:ok, ndt} = NaiveDateTime.new(attrs.start_date, attrs.start_time)
    tz = Partners.organization_timezone(org_id)
    dt = DateTime.from_naive!(ndt, tz)
    DateTime.shift_zone!(dt, "Etc/UTC")
  end

  defp start_at(%{start_at: start_at} = _attrs, _organization_id) do
    start_at
  end

  @spec start_at(map(), non_neg_integer) :: map()
  defp fix_attrs(attrs, org_id) do
    # compute start_at if not set
    start_at = start_at(attrs, org_id)

    attrs
    |> Map.put(:start_at, start_at)
    # set the initial value of the next firing of the trigger
    |> Map.put(:next_trigger_at, start_at)
  end

  @doc false
  @spec create_trigger(map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger(attrs) do
    %Trigger{}
    |> Trigger.changeset(attrs |> fix_attrs(Repo.get_organization_id()))
    |> Repo.insert()
  end

  @doc """
  Updates the triggger
  """
  @spec update_trigger(Trigger.t(), map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger(%Trigger{} = trigger, attrs) do
    trigger
    |> Trigger.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of triggers filtered by args
  """
  @spec list_triggers(map()) :: [Trigger.t()]
  def list_triggers(args) do
    Repo.list_filter(args, Trigger, &Repo.opts_with_name/2, &Repo.filter_with/2)
  end

  @doc """
  Return the count of triggers, using the same filter as list_triggers
  """
  @spec count_triggers(map()) :: integer
  def count_triggers(args),
    do: Repo.count_filter(args, Trigger, &Repo.filter_with/2)
end
