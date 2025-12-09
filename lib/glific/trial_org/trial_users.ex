defmodule Glific.TrialUsers do
  @moduledoc """
  Schema for trial organization data
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          username: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          organization_name: String.t() | nil,
          otp_entered: boolean() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime_usec | nil
        }

  @required_fields [
    :username,
    :email,
    :phone
  ]
  @optional_fields [
    :organization_name,
    :otp_entered
  ]

  schema "trial_users" do
    field :username, :string
    field :organization_name, :string
    field :email, :string
    field :phone, :string
    field(:otp_entered, :boolean, default: false)
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TrialUsers.t(), map()) :: Ecto.Changeset.t()
  def changeset(trial_org_data, attrs) do
    trial_org_data
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:phone, :email])
  end
end
