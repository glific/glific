defmodule Glific.WhatsappForms.WhatsappFormRevision do
  @moduledoc """
  Schema for storing revisions of WhatsApp forms.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Partners.Organization
  alias Glific.Users.User
  alias Glific.WhatsappForms.WhatsappForm

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          revision_number: non_neg_integer() | nil,
          definition: map() | nil,
          whatsapp_form_id: non_neg_integer() | nil,
          user_id: non_neg_integer() | nil,
          organization_id: non_neg_integer() | nil,
          whatsapp_form: WhatsappForm.t() | Ecto.Association.NotLoaded.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          organization: Organization.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [:definition, :whatsapp_form_id, :user_id, :organization_id]
  @optional_fields [:revision_number]

  schema "whatsapp_form_revisions" do
    field(:revision_number, :integer)
    field(:definition, :map)
    field(:is_current, :boolean, virtual: true, default: false)

    belongs_to(:whatsapp_form, WhatsappForm)
    belongs_to(:user, User)
    belongs_to(:organization, Organization)

    timestamps()
  end

  @doc """
  Standard changeset for WhatsApp form revisions.
  """
  @spec changeset(WhatsappFormRevision.t(), map()) :: Ecto.Changeset.t()
  def changeset(whatsapp_form_revision, attrs) do
    whatsapp_form_revision
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
