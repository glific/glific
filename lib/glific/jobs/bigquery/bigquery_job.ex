defmodule Glific.Jobs.BigqueryJob do
  @moduledoc """
  Book keeping table to keep track of the last job that we processed from the
  messages belonging to the organization
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Messages.Message,
    Partners.Organization
  }

  @required_fields [:organization_id]
  @optional_fields [:message_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          table_id: non_neg_integer | nil,
          table: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "bigquery_jobs" do
    belongs_to :message, Message
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(BigqueryJob.t(), map()) :: Ecto.Changeset.t()
  def changeset(search, attrs) do
    search
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:organization_id)
    |> unique_constraint(:message_id)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:organization_id)
  end
end
