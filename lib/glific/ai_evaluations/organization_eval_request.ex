defmodule Glific.AIEvaluations.OrganizationEvalRequest do
  @moduledoc """
  Schema for organization-level requests to access the AI Evaluations feature.
  One record per organization; status tracks the lifecycle of the request.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AIEvaluations.OrganizationEvalRequest,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          status: String.t(),
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_statuses ~w(requested approved rejected)
  @required_fields [:organization_id]
  @optional_fields [:status]

  schema "organization_eval_requests" do
    field(:status, :string, default: "requested")
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset for creating and updating organization eval requests.
  """
  @spec changeset(OrganizationEvalRequest.t(), map()) :: Ecto.Changeset.t()
  def changeset(request, attrs) do
    request
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> assoc_constraint(:organization)
    |> unique_constraint(:organization_id)
  end
end
