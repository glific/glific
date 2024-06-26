defmodule Glific.GCS.GcsJob do
  @moduledoc """
  Book keeping table to keep track of the last job that we processed from the
  messages belonging to the organization
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Messages.MessageMedia,
    Partners.Organization
  }

  @required_fields [:organization_id, :type]
  @optional_fields [:message_media_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          message_media_id: non_neg_integer | nil,
          type: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "gcs_jobs" do
    field :type, :string
    belongs_to :message_media, MessageMedia
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(GcsJob.t(), map()) :: Ecto.Changeset.t()
  def changeset(gcs_job, attrs) do
    gcs_job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:organization_id)
    |> unique_constraint(:message_media_id)
    |> foreign_key_constraint(:message_media_id)
    |> foreign_key_constraint(:organization_id)
  end
end
