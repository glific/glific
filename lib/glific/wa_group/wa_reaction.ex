defmodule Glific.WaGroup.WaReaction do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Partners.Organization,
    Repo,
    WAGroup.WAMessage,
    WaGroup.WaReaction
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          bsp_id: String.t() | nil,
          reaction: String.t() | nil,
          wa_message_id: non_neg_integer() | nil,
          wa_message: WAMessage | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  @required_fields [
    :bsp_id,
    :wa_message_id,
    :contact_id,
    :organization_id,
    :reaction
  ]

  @optional_fields []

  schema "wa_reactions" do
    field :bsp_id, :string
    field :reaction, :string
    belongs_to :wa_message, WAMessage
    belongs_to :contact, Contact
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WaReaction.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_reaction, attrs) do
    wa_reaction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Creates a WA Reaction

  Whatsapp only allows one reaction per user per message, but maytapi broadcasts all reactions
  so we do an upsert in that case
  """
  @spec create_wa_reaction(map()) :: {:ok, WaReaction.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_reaction(attrs) do
    %WaReaction{}
    |> changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:reaction, :updated_at]},
      conflict_target: [:wa_message_id, :contact_id],
      returning: true
    )
  end
end
