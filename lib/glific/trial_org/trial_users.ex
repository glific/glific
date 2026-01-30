defmodule Glific.TrialUsers do
  @moduledoc """
  Schema for trial organization data
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Repo
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
          updated_at: :utc_datetime | nil
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
  Creates a trial user
  """
  @spec create_trial_user(map()) :: {:ok, TrialUsers.t()} | {:error, Ecto.Changeset.t()}
  def create_trial_user(params) do
    %TrialUsers{}
    |> changeset(params)
    |> Repo.insert()
  end

  @doc """
  Updates a trial user
  """
  @spec update_trial_user(TrialUsers.t(), map()) ::
          {:ok, TrialUsers.t()} | {:error, Ecto.Changeset.t()}
  def update_trial_user(%TrialUsers{} = trial_user, attrs) do
    trial_user
    |> changeset(attrs)
    |> Repo.update()
  end

  @spec validate_email_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_email_format(changeset) do
    validate_change(changeset, :email, fn :email, email ->
      case Pow.Ecto.Schema.Changeset.validate_email(email) do
        :ok -> []
        {:error, reason} -> [email: reason]
      end
    end)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TrialUsers.t(), map()) :: Ecto.Changeset.t()
  def changeset(trial_org_data, attrs) do
    trial_org_data
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_email_format()
    |> unique_constraint(:phone)
    |> unique_constraint(:email)
  end
end
