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
    :flow_id,
    :enabled_days
  ]

  @type t() :: %__MODULE__{
          enabled: boolean | nil,
          start_time: :time | nil,
          end_time: :time | nil,
          enabled_days: map() | nil,
          flow_id: non_neg_integer | nil
        }

  embedded_schema do
    field :enabled, :boolean
    field :start_time, :time
    field :end_time, :time
    belongs_to :flow, Flow
    field :enabled_days, {:array, :map}
  end

  @doc """
  Standard changeset pattern for embedded schema
  """
  @spec out_of_office_changeset(OutOfOffice.t(), map()) :: Ecto.Changeset.t()
  def out_of_office_changeset(out_of_office, attrs) do
    out_of_office
    |> cast(attrs, @optional_fields)
  end
end
