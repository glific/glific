defmodule Glific.Flows.FlowGlobalKeyword do
  @moduledoc """
  The flow global keyword object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    Repo
  }

  @required_fields [:name, :flow_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "flow_global_keywords" do
    field :name, :string
    belongs_to :flow, Flow
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowGlobalKeyword.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_global_keyword, attrs) do
    flow_global_keyword
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  @spec create_flow_global_keyword(map()) ::
          {:ok, FlowGlobalKeyword.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_global_keyword(attrs \\ %{}) do
    %FlowGlobalKeyword{}
    |> FlowGlobalKeyword.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_global_keywords :: [String.t()]
  def get_global_keywords do
    FlowGlobalKeyword
    |> select([g], g.name)
    |> Repo.all()
  end

  @spec list_flow_global_keywords() :: [FlowGlobalKeyword.t()]
  def list_flow_global_keywords(),
    do: Repo.all(FlowGlobalKeyword)
end
