defmodule Glific.Partners.OrganizationSettings.OutOfOffice do
  @moduledoc """
  The Glific abstraction to represent the organization settings of out of office
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.Flow

  @optional_fields [
    :enabled,
    :start_time,
    :end_time,
    :flow_id
  ]

  @enabled_days_optional_fields [
    :monday,
    :tuesday,
    :wednesday,
    :thursday,
    :friday,
    :saturday,
    :sunday
  ]

  @type t() :: %__MODULE__{
          enabled: boolean | nil,
          start_time: :utc_datetime | nil,
          end_time: :utc_datetime | nil,
          enabled_days: map() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil
        }

  embedded_schema do
    field :enabled, :boolean
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    belongs_to :flow, Flow

    embeds_one :enabled_days, EnabledDays, on_replace: :update do
      field :monday, :boolean
      field :tuesday, :boolean
      field :wednesday, :boolean
      field :thursday, :boolean
      field :friday, :boolean
      field :saturday, :boolean
      field :sunday, :boolean
    end
  end

  @spec out_of_office_changeset(OutOfOffice.t(), map()) :: Ecto.Changeset.t()
  def out_of_office_changeset(out_of_office, attrs) do
    out_of_office
    |> cast(attrs, @optional_fields)
    |> cast_embed(:enabled_days, with: &enabled_days_changeset/2)
  end

  @spec enabled_days_changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def enabled_days_changeset(enabled_days, attrs) do
    enabled_days
    |> cast(attrs, @enabled_days_optional_fields)
  end
end
