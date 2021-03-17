defmodule Glific.Flows.FlowResult do
  @moduledoc """
  Table which stores the flow results for each run of a contact through a flow
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Partners.Organization,
    Repo
  }

  @required_fields [
    :contact_id,
    :flow_context_id,
    :flow_id,
    :flow_uuid,
    :flow_version,
    :organization_id
  ]
  @optional_fields [:results]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          results: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_context_id: non_neg_integer | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow_version: integer() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_results" do
    field :results, :map, default: %{}

    # Note that this is not a foreign key since contexts are cleaned up from the DB on a
    # periodic basis
    field :flow_context_id, :integer

    field :flow_version, :integer

    field :flow_uuid, Ecto.UUID

    belongs_to :contact, Contact
    belongs_to :flow, Flow
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowResult.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_revision, attrs) do
    flow_revision
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:flow_context_id)
  end

  @doc false
  @spec upsert_flow_result(map()) :: {:ok, FlowResult.t()} | {:error, Ecto.Changeset.t()}
  def upsert_flow_result(attrs) do
    case Repo.get_by(FlowResult, %{flow_context_id: attrs.flow_context_id}) do
      nil -> %FlowResult{} |> changeset(attrs) |> Repo.insert()
      flow_result -> flow_result |> changeset(attrs) |> Repo.update()
    end
  end
end
