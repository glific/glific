defmodule Glific.Dialogflow.Intent do
  @moduledoc """
  The intent object which has the intent information from any classifiers
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.{Partners.Organization, Repo}

  @required_fields [:name, :organization_id]
  @optional_fields []

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "intents" do
    field :name, :string

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Intent.t(), map()) :: Ecto.Changeset.t()
  def changeset(intent, attrs) do
    intent
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end

  @doc """
  Create an Intent for the NLP framework
  """
  @spec create_intent(map()) :: Intent.t()
  def create_intent(attrs),
  do:
    %Intent{}
    |> changeset(attrs)
    |> Repo.insert()

  @doc """
  Get a list of all the intent names.
  """
  @spec get_intent_name_list(non_neg_integer) :: list()
  def get_intent_name_list(org_id),
    do:
      Intent
      |> where([i], i.organization_id == ^org_id)
      |> select([i], i.name)
      |> Repo.all()
end
