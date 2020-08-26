defmodule Glific.Partners.OrganizationSettings.OutOfOffice do
  @moduledoc """
  The Glific abstraction to represent the organization settings of out of office
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.Flow
  alias Glific.Partners.OrganizationSettings.OutOfOffice.EnabledDay

  @optional_fields [
    :enabled,
    :start_time,
    :end_time,
    :flow_id
  ]

  @type t() :: %__MODULE__{
          enabled: boolean | nil,
          start_time: :time | nil,
          end_time: :time | nil,
          enabled_days: map() | nil,
          flow_id: non_neg_integer | nil
        }

  @primary_key false
  embedded_schema do
    field :enabled, :boolean
    field :start_time, :time
    field :end_time, :time
    belongs_to :flow, Flow

    embeds_many :enabled_days, EnabledDay, on_replace: :raise
  end

  @doc """
  Standard changeset pattern for embedded schema
  """
  @spec out_of_office_changeset(OutOfOffice.t(), map()) :: Ecto.Changeset.t()
  def out_of_office_changeset(out_of_office, attrs) do
    out_of_office
    |> cast(attrs, @optional_fields)
    |> cast_embed(:enabled_days, with: &EnabledDay.enabled_day_changeset/2)
  end
end

defmodule Glific.Partners.OrganizationSettings.OutOfOffice.EnabledDay do
  @moduledoc """
  The Glific abstraction to represent the out of office enabled day schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [
    :id,
    :enabled
  ]

  @primary_key false
  embedded_schema do
    field :id, :integer, primary_key: true
    field :enabled, :boolean
  end

  @doc """
  Changeset pattern for embedded schema of enabled_day
  """
  @spec enabled_day_changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def enabled_day_changeset(enabled_day, attrs) do
    enabled_day
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:id, less_than_or_equal_to: 7)
    |> validate_number(:id, greater_than_or_equal_to: 1)
  end
end
