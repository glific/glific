defmodule Glific.Topic do
  @moduledoc """
  The Topic object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
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
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "topics" do
    field :uuid, Ecto.UUID
    field :name, :string

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Glific.Flows.Topic.list_topic()
  Standard changeset pattern we use for all data types

  """
  @spec changeset(any(), map()) :: Ecto.Changeset.t()
  def changeset(topic, attrs) do
    topic
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end

  @doc """
  Given a organization id, retrieve all the topics for organization
  """
  @spec get_all_topics(non_neg_integer) :: [Topic.t()]
  def get_all_topics(organization_id) do
    query =
      Topic
      |> where([m], m.organization_id == ^organization_id)
      |> select([m], %{uuid: m.uuid, name: m.name})

    Repo.all(query)
  end

  @doc """
  Creates a topic.

  ## Examples

      iex> create_topic(%{field: value})
      {:ok, %Topic{}}

      iex> create_topic(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_topic(map()) ::
          {:ok, Topic.t()} | {:error, Ecto.Changeset.t()}
  def create_topic(%{organization_id: organization_id} = attrs) do
    uuid = Ecto.UUID.generate()

    attrs =
      attrs
      |> Map.put(:uuid, uuid)
      |> Map.put(:organization_id, organization_id)

    %Topic{}
    |> Topic.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [name: attrs.name]],
      conflict_target: [:name, :organization_id],
      returning: true
    )
  end

  @doc """
  Return the count of topics, using the same filter as list_topics
  """
  @spec list_topics(map()) :: list()
  def list_topics(args) do
    Repo.list_filter(args, Topic, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2)
  end

  @doc """
  Return the count of topics, using the same filter as list_topics
  """
  @spec count_topics(map()) :: integer
  def count_topics(args),
    do: Repo.count_filter(args, Topic, &Repo.filter_with/2)
end
