defmodule Glific.Partners.Provider do
  @moduledoc """
  Provider are the third party Business Service providers who will give a access of WhatsApp API
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  # define all the required fields for provider
  @required_fields [
    :name,
    :shortcode,
    :keys,
    :secrets
  ]

  # define all the optional fields for provider
  @optional_fields [:group, :description]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          shortcode: String.t() | nil,
          group: String.t() | nil,
          description: String.t() | nil,
          is_required: boolean(),
          keys: map() | nil,
          secrets: map() | nil
        }

  @schema_prefix "global"
  schema "providers" do
    field :name, :string
    field :shortcode, :string
    field :group, :string
    field :description, :string
    field :is_required, :boolean, default: false

    field :keys, :map
    field :secrets, :map
    has_many :organizations, Glific.Partners.Organization, foreign_key: :bsp_id
    has_one :credential, Glific.Partners.Credential

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(Provider.t(), map()) :: Ecto.Changeset.t()
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name])
  end

  @doc """
    A centralize function to get the currently active provider module.
    As this point of time we can not construct this module name dynamically
    that's why these are static for now.
  """
  @spec bsp_module(binary | non_neg_integer, any) :: any()
  def bsp_module(org_id, :template) do
    organization = Glific.Partners.organization(org_id)

    organization.bsp.shortcode
    |> case do
      "gupshup" -> Glific.Providers.Gupshup.Template
      "gupshup_enterprise" -> Glific.Providers.GupshupEnterprise.Template
      _ -> raise("#{organization.bsp.shortcode} Provider Not found.")
    end
  end

  def bsp_module(org_id, _) do
    organization = Glific.Partners.organization(org_id)

    organization.bsp.shortcode
    |> case do
      "gupshup" -> Glific.Providers.Gupshup
      "gupshup_enterprise" -> Glific.Providers.GupshupEnterprise
      _ -> raise("#{organization.bsp.shortcode} Provider Not found.")
    end
  end
end
