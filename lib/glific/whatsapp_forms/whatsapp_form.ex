defmodule Glific.WhatsappForms.WhatsappForm do
  @moduledoc """
  Whatsapp Form schema.
  """
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Glific.Partners.Organization
  alias Glific.Enums.WhatsappFormStatus

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t(),
          description: String.t() | nil,
          meta_flow_id: String.t(),
          status: String.t(),
          definition: map(),
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  @required_fields [
    :name,
    :meta_flow_id,
    :status,
    :definition,
    :organization_id
  ]

  @optional_fields [:description]

  schema "whatsapp_forms" do
    field(:name, :string)
    field(:description, :string)
    field(:meta_flow_id, :string)
    field(:status, WhatsappFormStatus)
    field(:definition, :map)

    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WhatsappForm.t(), map()) :: Ecto.Changeset.t()
  def changeset(whatsapp_form, attrs) do
    whatsapp_form
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
