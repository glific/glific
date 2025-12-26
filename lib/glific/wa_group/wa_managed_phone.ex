defmodule Glific.WAGroup.WAManagedPhone do
  @moduledoc """
  Schema to manage the phone numbers for each org that are our
  peek into the happenings on a WhatsApp Group
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Partners.Organization,
    WAGroup.WAManagedPhone
  }

  @required_fields [
    :phone,
    :phone_id,
    :organization_id,
    :contact_id
  ]

  @optional_fields [
    :label,
    :status,
    :product_id
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          phone: String.t() | nil,
          phone_id: non_neg_integer() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          status: String.t() | nil,
          product_id: String.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "wa_managed_phones" do
    field :label, :string
    field :phone, :string

    # these are associated with the whatsapp api provider
    # using maytapi as template
    field :phone_id, :integer

    field :status, :string
    field :product_id, :string

    belongs_to(:organization, Organization)
    belongs_to(:contact, Contact)
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(WAManagedPhone.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_managed_phone, attrs) do
    wa_managed_phone
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:contact_id)
  end
end
