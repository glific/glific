defmodule Glific.Partners.Setting do
  @moduledoc """
  The Glific abstraction to represent the organization setting
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  @optional_fields [
    :low_balance_threshold,
    :report_frequency,
    :run_flow_each_time,
    :send_warning_mail,
    :bsp_balance_limit
  ]

  @type t() :: %__MODULE__{
          low_balance_threshold: non_neg_integer() | nil,
          report_frequency: String.t() | nil,
          run_flow_each_time: boolean() | nil,
          send_warning_mail: boolean() | nil,
          bookmarks: map() | nil,
          bsp_balance_limit: non_neg_integer() | nil
        }

  @primary_key false
  embedded_schema do
    field :low_balance_threshold, :integer, default: 10
    field :report_frequency, :string, default: "WEEKLY"
    field :run_flow_each_time, :boolean, default: false
    field :send_warning_mail, :boolean, default: false
    field :bookmarks, :map, default: %{}
    field :bsp_balance_limit, :integer, default: 3
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
