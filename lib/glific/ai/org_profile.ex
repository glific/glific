defmodule Glific.AI.OrgProfile do
  @moduledoc """
  Standing instructions for one organization, applied to every Glific AI answer.

  For example: *low-literacy audience, keep messages under 40 words*. One row per
  organization.

  Live reads always beat this profile — never record here what a tool can look up.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Users.User
  }

  @required_fields [:organization_id]
  @optional_fields [:content, :updated_by_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          content: String.t() | nil,
          updated_by_id: non_neg_integer | nil,
          updated_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "glific_ai_org_profiles" do
    field :content, :string, default: ""

    belongs_to :updated_by, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:updated_by_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(:organization_id)
  end
end
