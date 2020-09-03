defmodule Glific.Partners.Organization do
  @moduledoc """
  Organizations are the group of users who will access the system
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Partners.OrganizationSettings.OutOfOffice,
    Partners.Provider,
    Settings.Language
  }

  # define all the required fields for organization
  @required_fields [
    :name,
    :shortcode,
    :email,
    :provider_id,
    :provider_key,
    :provider_phone,
    :default_language_id
  ]

  # define all the optional fields for organization
  @optional_fields [
    :contact_id,
    :is_active,
    :timezone
    # commenting this out, since the tests were giving me an error
    # about cast_embed etc
    # :out_of_office
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          shortcode: String.t() | nil,
          email: String.t() | nil,
          provider_id: non_neg_integer | nil,
          provider: Provider.t() | Ecto.Association.NotLoaded.t() | nil,
          provider_key: String.t() | nil,
          provider_phone: String.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          default_language_id: non_neg_integer | nil,
          default_language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          out_of_office: OutOfOffice.t() | nil,
          hours: list() | nil,
          days: list() | nil,
          is_active: boolean() | true,
          timezone: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "organizations" do
    field :name, :string
    field :shortcode, :string

    field :email, :string

    field :provider_phone, :string
    field :provider_key, :string

    # lets cache the start/end hours in here
    # to make it easier on the flows
    field :hours, {:array, :time}, virtual: true
    field :days, {:array, :integer}, virtual: true

    belongs_to :provider, Provider
    belongs_to :contact, Contact
    belongs_to :default_language, Language

    embeds_one :out_of_office, OutOfOffice, on_replace: :update

    field :is_active, :boolean, default: true

    field :timezone, :string, default: "Asia/Kolkata"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Organization.t(), map()) :: Ecto.Changeset.t()
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> add_out_of_office_if_missing()
    |> cast_embed(:out_of_office, with: &OutOfOffice.out_of_office_changeset/2)
    |> validate_required(@required_fields)
    |> unique_constraint(:shortcode)
    |> unique_constraint(:email)
    |> unique_constraint(:provider_phone)
    |> unique_constraint(:contact_id)
  end

  defp add_out_of_office_if_missing(
         %Ecto.Changeset{data: %Organization{out_of_office: nil}} = changeset
       ) do
    out_of_office_default_data = %{
      enabled: false,
      enabled_days: [
        %{enabled: false, id: 1},
        %{enabled: false, id: 2},
        %{enabled: false, id: 3},
        %{enabled: false, id: 4},
        %{enabled: false, id: 5},
        %{enabled: false, id: 6},
        %{enabled: false, id: 7}
      ]
    }

    changeset
    |> put_change(:out_of_office, out_of_office_default_data)
  end

  defp add_out_of_office_if_missing(changeset) do
    changeset
  end
end
