defmodule Glific.WhatsappForms.WhatsappForm do
  @moduledoc """
  Whatsapp Form schema.
  """
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Enums.WhatsappFormCategory
  alias Glific.Enums.WhatsappFormStatus
  alias Glific.Partners.Organization

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          meta_flow_id: String.t() | nil,
          status: String.t(),
          definition: map(),
          categories: [],
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :name,
    :meta_flow_id,
    :definition,
    :categories,
    :organization_id
  ]

  @optional_fields [:description, :status]

  schema "whatsapp_forms" do
    field(:name, :string)
    field(:description, :string)
    field(:meta_flow_id, :string)
    field(:status, WhatsappFormStatus, default: "draft")
    field(:definition, :map, default: %{})
    field(:categories, {:array, WhatsappFormCategory}, default: [])

    belongs_to :organization, Organization
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WhatsappForm.t(), map()) :: Ecto.Changeset.t()
  def changeset(whatsapp_form, attrs) do
    whatsapp_form
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end
end
