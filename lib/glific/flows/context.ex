defmodule Glific.Flows.Context do
  @moduledoc """
  When we are running a flow, we are running it in the context of a
  contact and/or a conversation (or other Glific data types). Let encapsulate
  this in a module and isolate the flow from the other aspects of Glific
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.Flow,
    Flows.Node,
    Repo,
    Settings.Language
  }

  @required_fields [:contact_id, :flow_uuid, :uuid_map]
  @optional_fields [:node_uuid]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          uuid_map: map() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "contexts" do
    field :uuid_map, :map

    belongs_to :contact, Contact

    belongs_to :flow, Flow, foreign_key: :flow_uuid, references: :uuid, primary_key: true

    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Context.t(), map()) :: Ecto.Changeset.t()
  def changeset(context, attrs) do
    context
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:flow_uuid)
    |> foreign_key_constraint(:node_uuid)
  end

  @doc """
  Set the language for a contact
  """
  @spec set_contact_language(Context.t(), String.t()) :: Context.t()
  def set_contact_language(context, language) do
    # get the language id
    {:ok, language_id} = Repo.fetch_by(Language, %{label: language})
    {:ok, contact} = Contacts.update_contact(context.contact, %{language_id: language_id})
    Map.put(context, :contact, contact)
  end

  @doc """
  Set the new node for the context
  """
  @spec set_node(Context.t(), Node.t()) :: Context.t()
  def set_node(context, node) do
    context
    |> Map.put(:node, node)
    |> Map.put(:node_uuid, node.uuid)
  end

  @doc """
  Execute one (or more) steps in a flow based on the message stream
  """
  @spec execute(Context.t(), [String.t()]) ::
          {:ok, Context.t(), [String.t()]} | {:error, String.t()}
  def execute(context, messages) when messages == [],
    do: {:ok, context, []}

  def execute(context, messages) do
    {:ok, context, messages} = Node.execute(context.node, context, messages)
    Context.execute(context, messages)
  end
end
