defmodule Glific.Triggers.Trigger do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  import Ecto.Query, warn: false

  alias Glific.{
    AccessControl.Role,
    Flows.Flow,
    Groups.Group,
    Partners.Organization
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
          hours: list() | nil,
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
    :days,
    :hours
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
    field :hours, {:array, :integer}, default: []

    field :is_active, :boolean, default: true
    field :is_repeating, :boolean, default: false

    belongs_to :organization, Organization
    many_to_many :roles, Role, join_through: "trigger_roles", on_replace: :delete

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
    |> validate_start_at()
    |> validate_frequency()
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:organization_id)
  end

  # @doc false
  #  if trigger start_at should always be greater than current time
  @spec validate_start_at(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_start_at(%{changes: changes} = changeset) when not is_nil(changes.start_at) do
    start_at = changeset.changes[:start_at]
    time = DateTime.utc_now()

    if DateTime.compare(time, start_at) == :lt,
      do: changeset,
      else:
        add_error(
          changeset,
          :start_at,
          "Trigger start_at should always be greater than current time"
        )
  end

  defp validate_start_at(changeset), do: changeset

  defp validate_frequency(changeset) do
    do_validate_frequency(changeset.changes)
    |> case do
      {:ok, updated_attrs} ->
        Map.put(changeset, :changes, updated_attrs)

      {:error, error} ->
        add_error(
          changeset,
          :frequency,
          error
        )
    end
  end

  defp do_validate_frequency(%{frequency: frequency} = attrs)
       when frequency in [["daily"], ["none"]] do
    {:ok, Map.merge(attrs, %{days: [], hours: []})}
  end

  defp do_validate_frequency(%{frequency: ["hourly"], hours: hours} = attrs) when hours != [] do
    valid_hours = Enum.reduce(0..23, [], fn hour, acc -> acc ++ [hour] end)

    Enum.all?(hours, fn hour -> hour in valid_hours end)
    |> case do
      true -> {:ok, Map.put(attrs, :days, [])}
      false -> {:error, "Cannot create Trigger with invalid hours"}
    end
  end

  defp do_validate_frequency(%{frequency: ["weekly"], days: days} = attrs) when days != [] do
    valid_days = Enum.reduce(1..7, [], fn day, acc -> acc ++ [day] end)

    Enum.all?(days, fn day -> day in valid_days end)
    |> case do
      true -> {:ok, Map.put(attrs, :hours, [])}
      false -> {:error, "Cannot create Trigger with invalid days"}
    end
  end

  defp do_validate_frequency(%{frequency: ["monthly"], days: days} = attrs) when days != [] do
    valid_days = Enum.reduce(1..31, [], fn day, acc -> acc ++ [day] end)

    Enum.all?(days, fn day -> day in valid_days end)
    |> case do
      true -> {:ok, Map.put(attrs, :hours, [])}
      false -> {:error, "Cannot create Trigger with invalid days"}
    end
  end

  defp do_validate_frequency(attrs),
    do: {:ok, attrs}
end
