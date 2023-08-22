defmodule Glific.Partners.Setting do
  @moduledoc """
  The Glific abstraction to represent the organization setting
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  @optional_fields [
    :report_frequency,
    :run_flow_each_time
  ]

  @type t() :: %__MODULE__{
    report_frequency: String.t() | nil,
    run_flow_each_time: boolean() | nil
  }

  @primary_key false
  embedded_schema do
    field :report_frequency, :string
    field :run_flow_each_time, :boolean, default: false
  end

  @doc """
  Standard changeset pattern for embedded schema
  """
  @spec setting_changeset(Setting.t(), map()) :: Ecto.Changeset.t()
  def setting_changeset(setting, attrs) do
    setting
    |> cast(attrs, @optional_fields)
  end
end
