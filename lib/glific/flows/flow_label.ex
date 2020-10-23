defmodule Glific.Flows.FlowLabel do
  @moduledoc """
  The flow label object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__
  alias Glific.{
    Flows.Flow,
    Partners.Organization,
    Repo
  }

  @required_fields [:uuid, :name, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
        }

  schema "flow_label" do
    field :uuid, Ecto.UUID
    field :name, :string

    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types

  """
  @spec changeset(any(), map()) :: Ecto.Changeset.t()
  def changeset(flow_label, attrs) do
    flow_label
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end

end
