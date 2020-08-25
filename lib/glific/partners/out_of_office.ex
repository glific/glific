defmodule Glific.Partners.OutOfOffice do
  @moduledoc """
  The Glific Abstraction to represent the organization settings of out of office
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.Flow

  @required_fields [
    :enabled
  ]

  @optional_fields [
    :start_time,
    :end_time,
    :enabled_days,
    :flow_id
  ]

  @type t() :: %__MODULE__{
        }

  embedded_schema do
    field :enabled, :boolean
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :enabled_days, :map
    belongs_to :flow, Flow
  end

  def out_of_office_changeset(out_of_office, attrs) do
    out_of_office
    |> cast(attrs, @required_fields ++ @optional_fields)
  end
end
