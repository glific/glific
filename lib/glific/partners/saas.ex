defmodule Glific.Partners.Saas do
  @moduledoc """
  Saas is the DB table that holds the various parameters we need to run the service.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{Partners.Organization, Repo}

  # define all the required fields for saas
  @required_fields [
    :name,
    :organization_id,
    :phone
  ]

  # define all the optional fields for saas
  @optional_fields [:email, :stripe_ids, :tax_rates]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          phone: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "saas" do
    field :name, :string
    field :phone, :string
    field :email, :string

    field :stripe_ids, :map
    field :tax_rates, :map

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(Saas.t(), map()) :: Ecto.Changeset.t()
  def changeset(saas, attrs) do
    saas
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name])
  end

  @doc """
  SaaS Phone to create admin accounts
  """
  @spec phone(String.t()) :: String.t()
  def phone(name \\ "Tides"),
    do: saas_field(name, :phone)

  @doc """
  SaaS organization id to store BQ data under the context
  of the SaaS org credentials (specifically global stats data)
  """
  @spec organization_id(String.t()) :: non_neg_integer
  def organization_id(name \\ "Tides"),
    do: saas_field(name, :organization_id)

  @doc """
  SaaS stripe ids for billing purpose, convert the string keys to atoms
  """
  @spec stripe_ids(String.t()) :: map()
  def stripe_ids(name \\ "Tides"),
    do: saas_field(name, :stripe_ids)

  @doc """
  SaaS primary email for the service and notifications

  """
  @spec primary_email(String.t()) :: map()
  def primary_email(name \\ "Tides"),
    do: saas_field(name, :email)

  @doc """
  SaaS tax rates for adding tax to subscription and invoices, convert the string keys to atoms
  """
  @spec tax_rates(String.t()) :: list()
  def tax_rates(name \\ "Tides"),
    do: saas_field(name, :tax_rates) |> Map.values()

  @spec saas_field(String.t(), atom()) :: any()
  defp saas_field(name, field) do
    Saas
    |> where([s], s.name == ^name)
    |> select([s], field(s, ^field))
    |> Repo.one!(skip_organization_id: true)
  end
end
