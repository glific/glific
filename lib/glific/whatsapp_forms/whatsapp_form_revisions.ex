defmodule Glific.WhatsappForms.WhatsappFormRevision do
  @moduledoc """
  Schema for storing revisions of WhatsApp forms.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Users.User
  alias Glific.WhatsappForms.WhatsappForm

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          revision_number: non_neg_integer(),
          definition: map(),
          whatsapp_form_id: non_neg_integer(),
          user_id: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [:revision_number, :definition, :whatsapp_form_id, :user_id]
  @optional_fields []

  schema "whatsapp_form_revisions" do
    field(:revision_number, :integer)
    field(:definition, :map)

    belongs_to :whatsapp_form, WhatsappForm
    belongs_to :user, User

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
