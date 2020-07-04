defmodule Glific.Flows.Category do
  @moduledoc """
  The Category object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Case,
    Exit,
    Router
  }

  @required_fields [:name, :exit_uuid, :router_uuid]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          exit_uuid: Ecto.UUID.t() | nil,
          exit: Exit.t() | Ecto.Association.NotLoaded.t() | nil,
          router_uuid: Ecto.UUID.t() | nil,
          router: Router.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "categories" do
    field :name, :string

    has_many :cases, Case

    belongs_to :router, Router, foreign_key: :router_uuid, references: :uuid, primary_key: true
    belongs_to :exit, Exit, foreign_key: :exit_uuid, references: :uuid, primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Category.t(), map()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:router_uuid)
    |> foreign_key_constraint(:exit_uuid)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Router.t()) :: {Category.t(), map()}
  def process(json, uuid_map, router) do
    category = %Category{
      uuid: json["uuid"],
      router_uuid: router.uuid,
      exit_uuid: json["exit_uuid"],
      name: json["name"]
    }

    {category, Map.put(uuid_map, category.uuid, {:category, category})}
  end

  @doc """
  Execute a category, given a message stream.
  """
  @spec execute(Category.t, map(), [String.t]) :: any
  def execute(category, uuid_map, message_stream) do
    # transfer control to the exit node
    {:ok, {:exit, exit}} = Map.fetch(uuid_map, category.exit_uuid)
    Exit.execute(exit, uuid_map, message_stream)
  end

end
