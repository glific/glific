<<<<<<< HEAD:lib/glific/partners/organization_data.ex
defmodule Glific.Partners.OrganizationData do
=======
defmodule Glific.Clients.OrganizationData do
>>>>>>> 8b86eba40f7d028c0e8a34de62af61cb3395059f:lib/glific/clients/organization_data.ex
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.Partners.Organization

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          key: String.t() | atom() | nil,
          description: String.t() | atom() | nil,
          json: map() | nil,
          text: String.t() | atom() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :key,
    :organization_id
  ]
  @optional_fields [
    :description,
    :json,
    :text
  ]

  schema "organization_data" do
    field :key, :string
    field :description, :string
    field :text, :string
    field :json, :map, default: %{}
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(OrganizationData.t(), map()) :: Ecto.Changeset.t()
  def changeset(organization_data, attrs) do
    organization_data
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:key, :organization_id])
  end
end
