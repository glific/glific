defmodule Glific.Registrations.Registration do
  @moduledoc """
  Registrations are the application form filled by users
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Registrations.Registration
  }

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
    :ip_address,
    :terms_agreed,
    :support_staff_account
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          org_details: map() | nil,
          platform_details: map() | nil,
          billing_frequency: String.t() | nil,
          finance_poc: map() | nil,
          submitter: map() | nil,
          signing_authority: map() | nil,
          has_submitted: boolean() | false,
          has_confirmed: boolean() | false,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          ip_address: String.t() | nil,
          terms_agreed: boolean() | false,
          support_staff_account: boolean() | true
        }

  schema "registrations" do
    field(:org_details, :map)
    field(:platform_details, :map)

    field(:billing_frequency, :string)

    field(:finance_poc, :map)

    field(:submitter, :map)

    field(:signing_authority, :map)

    field(:has_submitted, :boolean, default: false)
    field(:has_confirmed, :boolean, default: false)
    field(:ip_address, :string)
    field(:terms_agreed, :boolean, default: false)
    field(:support_staff_account, :boolean, default: true)
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
  end

  @doc false
  @spec to_minimal_map(Registration.t()) :: map()
  def to_minimal_map(registration) do
    Map.take(registration, [:id | @required_fields ++ @optional_fields])
  end
end
