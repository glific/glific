defmodule Glific.Partners.OrganizationSettings.RegxFlow do
  @moduledoc """
  The Glific abstraction to represent the regular expression flow
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.Flow

  @optional_fields []

  @required_fields [
    :flow_id,
    :regx,
    :regx_opt
  ]

  @type t() :: %__MODULE__{
          flow_id: non_neg_integer | nil,
          regx: String.t() | nil,
          regx_opt: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :regx, :string
    field :regx_opt, :string
    belongs_to :flow, Flow
  end

  @doc """
  Standard changeset pattern for embedded schema
  """
  @spec regx_flow_changeset(RegxFlow.t(), map()) :: Ecto.Changeset.t()
  def regx_flow_changeset(regx_flow, attrs) do
    regx_flow
    |> cast(attrs, @optional_fields ++ @required_fields)
    |> validate_required(@required_fields)
  end
end
