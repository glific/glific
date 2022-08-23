defmodule Glific.Notifications.Notification do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  import Ecto.Query, warn: false

  alias Glific.{Partners.Organization}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          category: String.t() | nil,
          entity: map() | nil,
          message: String.t() | nil,
          severity: String.t() | nil,
          is_read: boolean() | false,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :category,
    :entity,
    :message
  ]

  @optional_fields [
    :severity,
    :organization_id,
    :is_read
  ]

  schema "notifications" do
    field :category, :string
    field :entity, :map
    field :message, :string
    field :severity, :string, default: "Warning"

    field :is_read, :boolean, default: false

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Notification.t(), map()) :: Ecto.Changeset.t()
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end
end
