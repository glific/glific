defmodule Glific.Flows.FlowLabel do
  @moduledoc """
  The flow label object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__
  alias Glific.{
    Flows.FlowLabel,
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
  Glific.Flows.FlowLabel.list_flow_label()
  Standard changeset pattern we use for all data types

  """
  @spec changeset(any(), map()) :: Ecto.Changeset.t()
  def changeset(flow_label, attrs) do
    flow_label
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end

  @doc """
  Given a organization id, retrieve all the flow labels for organization
  """
  @spec get_all_flowlabel(non_neg_integer) :: [FlowLabel.t()]
  def get_all_flowlabel(organization_id) do
      query =
        FlowLabel
        |> where([m], m.organization_id == ^organization_id)
      Repo.all(query)
  end

  @doc """
  Creates a flow_label.

  ## Examples

      iex> create_flow_label(%{field: value})
      {:ok, %FlowLabel{}}

      iex> create_flow_label(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_flow_label(map(), non_neg_integer) :: {:ok, FlowLabel.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_label(attrs, organization_id) do
    uuid = Ecto.UUID.generate
    attrs = attrs
            |>Map.put(:uuid, uuid)
            |>Map.put(:organization_id, organization_id)
    %FlowLabel{}
    |> FlowLabel.changeset(attrs)
    |> Repo.insert()
  end
end
