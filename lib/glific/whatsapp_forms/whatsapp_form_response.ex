defmodule Glific.WhatsappForms.WhatsappFormResponse do
  @moduledoc """
  Whatsapp Form Response schema.
  """
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Contacts.Contact
  alias Glific.Partners.Organization
  alias Glific.WhatsappForms.WhatsappForm

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          raw_response: map(),
          submitted_at: DateTime.t() | nil,
          whatsapp_form_id: non_neg_integer() | nil,
          contact_id: non_neg_integer() | nil,
          organization_id: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :raw_response,
    :submitted_at,
    :contact_id,
    :whatsapp_form_id,
    :organization_id
  ]

  @optional_fields []

  schema "whatsapp_forms_responses" do
    field(:raw_response, :map, default: %{})
    field(:submitted_at, :utc_datetime_usec)

    belongs_to :contact, Contact
    belongs_to :whatsapp_form, WhatsappForm
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WhatsappFormResponse.t(), map()) :: Ecto.Changeset.t()
  def changeset(whatsapp_form_response, attrs) do
    whatsapp_form_response
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
