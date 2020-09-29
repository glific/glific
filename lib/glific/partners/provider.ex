defmodule Glific.Partners.Provider do
  @moduledoc """
  Provider are the third party Business Service providers who will give a access of WhatsApp API
  """

  use Ecto.Schema
  import Ecto.Changeset

  # define all the required fields for provider
  @required_fields [
    :name,
    :shortcode,
    :keys,
    :secrets
  ]

  # define all the optional fields for provider
  @optional_fields [:group]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          shortcode: String.t() | nil,
          group: String.t() | nil,
          is_required: boolean(),
          keys: map() | nil,
          secrets: map() | nil
        }

  schema "providers" do
    field :name, :string
    field :shortcode, :string
    field :group, :string
    field :is_required, :boolean, default: false

    field :keys, :map
    field :secrets, :map
    has_many :organizations, Glific.Partners.Organization

    timestamps(type: :utc_datetime)
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
  end
end
