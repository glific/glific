defmodule Glific.Registrations.Registration do
  @moduledoc """
  Registrations are the application form filled by users
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.Partners.Organization
  alias __MODULE__

  # define all the required fields for organization
  @required_fields [
    :organization_id
  ]

  # define all the optional fields for organization
  @optional_fields [
    :org_details,
    :platform_details,
    :billing_frequency,
    :finance_poc,
    :submitter,
    :signing_authority,
    :has_submitted,
    :has_confirmed,
    :organization_id
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          org_details: map(),
          platform_details: map(),
          billing_frequency: String.t(),
          finance_poc: map(),
          submitter: map(),
          signing_authority: map(),
          has_submitted: boolean(),
          has_confirmed: boolean(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "registrations" do
    field(:org_details, :map)
    field(:platform_details, :map)

    field(:billing_frequency, :string)

    field(:finance_poc, :map)

    field(:submitter, :map)

    field(:signing_authority, :map)

    field(:has_submitted, :boolean)
    field(:has_confirmed, :boolean)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Registration.t(), map()) :: Ecto.Changeset.t()
  def changeset(registration, attrs) do
    registration
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end
end
