defmodule Glific.Partners.Organization do
  @moduledoc """
  Organizations are the group of users who will access the system
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Partners.OrganizationSettings.OutOfOffice,
    Partners.Provider,
    Repo,
    Settings.Language
  }

  # define all the required fields for organization
  @required_fields [
    :name,
    :shortcode,
    :email,
    :bsp_id,
    :default_language_id
  ]

  # define all the optional fields for organization
  @optional_fields [
    :contact_id,
    :is_active,
    :timezone,
    :active_language_ids,
    :session_limit,
    :organization_id,
    :signature_phrase
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
          bsp_id: non_neg_integer | nil,
          bsp: Provider.t() | Ecto.Association.NotLoaded.t() | nil,
          services: map(),
          root_user: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          default_language_id: non_neg_integer | nil,
          default_language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          out_of_office: OutOfOffice.t() | nil,
          hours: list() | nil,
          days: list() | nil,
          is_active: boolean() | true,
          timezone: String.t() | nil,
          active_language_ids: [integer] | [],
          languages: [Language.t()] | nil,
          session_limit: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          signature_phrase: String.t(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "organizations" do
    field :name, :string
    field :shortcode, :string

    field :email, :string

    # we'll cache all the services here
    field :services, :map, virtual: true, default: %{}

    # we'll cache the root user of the org here, this gives
    # us a permissioning object for calls from gupshup and
    # floweditor
    field :root_user, :map, virtual: true

    # lets cache the start/end hours in here
    # to make it easier on the flows
    field :hours, {:array, :time}, virtual: true
    field :days, {:array, :integer}, virtual: true

    belongs_to :bsp, Provider, foreign_key: :bsp_id
    belongs_to :contact, Contact
    belongs_to :default_language, Language

    embeds_one :out_of_office, OutOfOffice, on_replace: :update

    field :is_active, :boolean, default: true

    field :timezone, :string, default: "Asia/Kolkata"

    field :active_language_ids, {:array, :integer}, default: []

    # new version of ecto was giving us an error if we set the inner_type ot Language
    field :languages, {:array, :any}, virtual: true

    field :session_limit, :integer, default: 60

    # this is just to make our friends in org id enforcer happy and to keep the code clean
    field :organization_id, :integer

    # webhook sign phrase, kept encrypted (soon)
    field :signature_phrase, :string, default: "super secret"

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
    |> validate_inclusion(:timezone, Tzdata.zone_list())
    |> validate_active_languages()
    |> validate_default_language()
    |> unique_constraint(:shortcode)
    |> unique_constraint(:email)
    |> unique_constraint(:contact_id)
  end

  defp validate_active_languages(changeset) do
    language_ids =
      Language
      |> select([l], l.id)
      |> Repo.all()

    changeset
    |> validate_subset(:active_language_ids, language_ids)
  end

  defp validate_default_language(changeset) do
    default_language_id = get_field(changeset, :default_language_id)
    active_language_ids = get_field(changeset, :active_language_ids)

    check_valid_language(changeset, default_language_id, active_language_ids)
  end

  defp check_valid_language(changeset, nil, _), do: changeset
  defp check_valid_language(changeset, _, nil), do: changeset

  defp check_valid_language(changeset, default_language_id, active_language_ids) do
    if default_language_id in active_language_ids,
      do: changeset,
      else:
        add_error(
          changeset,
          :default_language_id,
          "default language must be updated according to active languages"
        )
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

defimpl FunWithFlags.Actor, for: Map do
  @moduledoc false

  @doc """
  All users are organization actors for now. At some point, we might make
  organization a group and isolate specific users

  Implemention of id for the map protocol
  """
  @spec id(map()) :: String.t()
  def id(%{organization_id: organization_id}) do
    "org:#{organization_id}"
  end
end
