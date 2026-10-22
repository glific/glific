defmodule Glific.Partners.Credential do
  @moduledoc """
  Organization's credentials
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.Partners.{
    Organization,
    Provider
  }

  alias Glific.WebChannel.JwtSecret

  @derive {ExAudit.Tracker, except: [:secrets]}

  @required_fields [:organization_id, :provider_id]
  @optional_fields [:keys, :secrets, :is_active, :is_valid]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          keys: map() | nil,
          secrets: map() | nil,
          is_active: boolean(),
          is_valid: boolean(),
          provider_id: non_neg_integer | nil,
          provider: Provider.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "credentials" do
    field :keys, :map, default: %{}
    field :secrets, Glific.Encrypted.Map

    field :is_active, :boolean, default: false
    field :is_valid, :boolean, default: true

    belongs_to :provider, Provider
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Credential.t(), map()) :: Ecto.Changeset.t()
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_jwt_secret()
    |> unique_constraint([:provider_id, :organization_id])
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:organization_id)
  end

  @spec validate_jwt_secret(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_jwt_secret(%{data: %Credential{secrets: old_secrets}} = changeset) do
    validate_change(changeset, :secrets, fn :secrets, secrets ->
      if is_map(secrets),
        do: Enum.map(JwtSecret.validate_new_secret(old_secrets, secrets), &{:secrets, &1}),
        else: []
    end)
  end
end
