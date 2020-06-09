defmodule Glific.Partners.Provider do
  @moduledoc """
  Provider are the third party Business Service providers who will give a access of WhatsApp API
  """

  use Ecto.Schema
  import Ecto.Changeset

  # define all the required fields for provider
  @required_fields [
    :name,
    :url,
    :api_end_point
  ]

  # define all the optional fields for provider
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          url: String.t() | nil
        }

  schema "providers" do
    field :name, :string
    field :url, :string
    field :api_end_point, :string

    has_many :organizations, Glific.Partners.Organization

    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(%Glific.Partners.Provider{}, map()) :: Ecto.Changeset.t()
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name])
    |> foreign_key_constraint(:organizations)
  end
end
