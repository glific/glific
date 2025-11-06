defmodule Glific.WhatsappForms.WhatsappForm do
  @moduledoc """
  Whatsapp Form schema.
  """
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Enums.WhatsappFormCategory,
    Enums.WhatsappFormStatus,
    Partners.Organization,
    Repo
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          meta_flow_id: String.t() | nil,
          status: String.t(),
          definition: map(),
          categories: [],
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :name,
    :meta_flow_id,
    :definition,
    :categories,
    :organization_id
  ]

  @optional_fields [:description, :status]

  schema "whatsapp_forms" do
    field(:name, :string)
    field(:description, :string)
    field(:meta_flow_id, :string)
    field(:status, WhatsappFormStatus, default: "draft")
    field(:definition, :map, default: %{})
    field(:categories, {:array, WhatsappFormCategory}, default: [])

    belongs_to :organization, Organization
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WhatsappForm.t(), map()) :: Ecto.Changeset.t()
  def changeset(whatsapp_form, attrs) do
    whatsapp_form
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end

  @doc """
  Creates a WhatsApp form record in the database
  """
  @spec create_whatsapp_form(map()) :: {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  def create_whatsapp_form(attrs) do
    %WhatsappForm{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a WhatsApp form record in the database
  """
  @spec update_whatsapp_form(non_neg_integer(), map()) ::
          {:ok, WhatsappForm.t()} | {:error, Ecto.Changeset.t()}
  def update_whatsapp_form(id, attrs) do
    whatsapp_form = Repo.get!(WhatsappForm, id)

    whatsapp_form
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Fetches a WhatsApp form by its ID
  """
  @spec get_whatsapp_form_by_id(non_neg_integer()) :: {:ok, WhatsappForm.t()} | {:error, any()}
  def get_whatsapp_form_by_id(id) do
    Repo.fetch_by(WhatsappForm, %{id: id})
  end
end
