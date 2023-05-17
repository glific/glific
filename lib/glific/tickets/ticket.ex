defmodule Glific.Tickets.Ticket do
  @moduledoc """
  Schema definition for the ticket table
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Partners.Organization,
    Users.User
  }

  @required_fields [:body, :contact_id, :status, :organization_id]
  @optional_fields [:user_id, :topic, :remarks]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          body: String.t() | nil,
          topic: String.t() | nil,
          status: String.t() | nil,
          remarks: String.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "tickets" do
    field(:body, :string)
    field(:topic, :string)
    field(:status, :string)
    field(:remarks, :string)

    belongs_to(:contact, Contact)
    belongs_to(:user, User)
    belongs_to(:organization, Organization)

    timestamps()
  end

  @doc false
  @spec changeset(Ticket.t(), map()) :: Ecto.Changeset.t()
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
