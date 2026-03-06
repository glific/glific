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
    Enums.OrganizationStatus,
    Partners.OrganizationSettings.OutOfOffice,
    Partners.OrganizationSettings.RegxFlow,
    Partners.Provider,
    Partners.Setting,
    Repo,
    Settings.Language
  }

  # define all the required fields for organization
  @required_fields [
    :name,
    :shortcode,
    :bsp_id,
    :default_language_id
  ]

  # define all the optional fields for organization
  @optional_fields [
    :email,
    :contact_id,
    :is_active,
    :is_approved,
    :status,
    :timezone,
    :active_language_ids,
    :session_limit,
    :organization_id,
    :signature_phrase,
    :last_communication_at,
    :fields,
    :team_emails,
    :newcontact_flow_id,
    :optin_flow_id,
    :is_suspended,
    :suspended_until,
    :parent_org,
    :is_trial_org,
    :trial_expiration_date,
    :deleted_at
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
          regx_flow: RegxFlow.t() | nil,
          newcontact_flow_id: non_neg_integer | nil,
          optin_flow_id: non_neg_integer | nil,
          hours: list() | nil,
          days: list() | nil,
          is_active: boolean() | true,
          is_approved: boolean() | false,
          status: String.t() | nil | atom(),
          timezone: String.t() | nil,
          active_language_ids: [integer] | [],
          languages: [Language.t()] | nil,
          session_limit: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          signature_phrase: binary | nil,
          last_communication_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          fields: map() | nil,
          team_emails: map() | nil,
          is_suspended: boolean() | false,
          suspended_until: DateTime.t() | nil,
          parent_org: String.t() | nil,
          setting: Setting.t() | nil,
          is_trial_org: boolean() | false,
          trial_expiration_date: :utc_datetime | nil,
          deleted_at: :utc_datetime | nil
        }

  schema "organizations" do
    field(:name, :string)
    field(:parent_org, :string)

    field(:shortcode, :string)

    field(:email, :string)

    # we'll cache all the services here
    field(:services, :map, virtual: true, default: %{})

    # we'll cache the root user of the org here, this gives
    # us a permission object for calls from gupshup and
    # flow editor
    field(:root_user, :map, virtual: true)

    # lets cache the start/end hours in here
    # to make it easier on the flows
    field(:hours, {:array, :time}, virtual: true)
    field(:days, {:array, :integer}, virtual: true)

    belongs_to(:bsp, Provider, foreign_key: :bsp_id)
    belongs_to(:contact, Contact)
    belongs_to(:default_language, Language)

    embeds_one(:out_of_office, OutOfOffice, on_replace: :update)
    embeds_one(:setting, Setting, on_replace: :update)
    embeds_one(:regx_flow, RegxFlow, on_replace: :update)

    # id of flow which gets triggered when new contact joins or optin's
    field(:newcontact_flow_id, :integer)
    field(:optin_flow_id, :integer)

    field(:is_active, :boolean, default: true)
    field(:is_approved, :boolean, default: false)

    field(:status, OrganizationStatus)

    field(:timezone, :string, default: "Asia/Kolkata")

    field(:active_language_ids, {:array, :integer}, default: [])

    # new version of ecto was giving us an error if we set the inner_type ot Language
    field(:languages, {:array, :any}, virtual: true)

    field(:session_limit, :integer, default: 60)

    # this is just to make our friends in org id enforcer happy and to keep the code clean
    field(:organization_id, :integer)

    # webhook sign phrase, kept encrypted (soon)
    field(:signature_phrase, Glific.Encrypted.Binary)

    field(:last_communication_at, :utc_datetime)

    field(:fields, :map, default: %{})
    field(:team_emails, :map, default: %{})

    # trial account support
    field(:is_trial_org, :boolean, default: false)
    field(:trial_expiration_date, :utc_datetime)

    # lets add support for suspending orgs briefly
    field(:is_suspended, :boolean, default: false)
    field(:suspended_until, :utc_datetime)

    # soft delete timestamp
    field(:deleted_at, :utc_datetime)

    # 2085
    # Lets create a virtual field for now to conditionally enable
    # the display of node uuids. We need an NGO friendly way to do this globally
    field(:is_flow_uuid_display, :boolean, default: false, virtual: true)

    # virtual field for roles and permission
    field(:is_roles_and_permission, :boolean, default: false, virtual: true)

    # A virtual field for now to conditionally enable contact profile feature for an organization
    field(:is_contact_profile_enabled, :boolean, default: false, virtual: true)

    # A virtual field for now to conditionally enable ticketing feature for an organization
    field(:is_ticketing_enabled, :boolean, default: false, virtual: true)

    # A virtual field for now to conditionally enable auto translation feature for an organization
    field(:is_auto_translation_enabled, :boolean, default: false, virtual: true)

    # A virtual field for now to conditionally enable whatsapp group feature for an organization
    field(:is_whatsapp_group_enabled, :boolean, default: false, virtual: true)

    # A virtual field for now to conditionally enable custom certificate feature for an organization
    field(:is_certificate_enabled, :boolean, default: false, virtual: true)

    # A virtual field for now to conditionally enable kaapi for an organization
    field(:is_kaapi_enabled, :boolean, default: false, virtual: true)

    field(:is_interactive_re_response_enabled, :boolean, default: false, virtual: true)

    field(:is_ask_me_bot_enabled, :boolean, default: false, virtual: true)

    field(:is_whatsapp_forms_enabled, :boolean, default: false, virtual: true)

    field(:high_trigger_tps_enabled, :boolean, default: false, virtual: true)

    field(:unified_api_enabled, :boolean, default: false, virtual: true)

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
    |> cast_embed(:regx_flow, with: &RegxFlow.regx_flow_changeset/2)
    |> cast_embed(:setting, with: &Setting.setting_changeset/2)
    |> validate_required(@required_fields)
    |> validate_inclusion(:timezone, Tzdata.zone_list())
    |> validate_active_languages()
    |> validate_default_language()
    |> unique_constraint(:shortcode)
    |> unique_constraint(:contact_id)
  end

  @doc false
  @spec to_minimal_map(Organization.t()) :: map()
  def to_minimal_map(organization) do
    Map.take(organization, [:id | @required_fields ++ @optional_fields])
  end

  @spec validate_active_languages(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_active_languages(changeset) do
    language_ids =
      Language
      |> select([l], l.id)
      |> Repo.all()

    changeset
    |> validate_subset(:active_language_ids, language_ids)
  end

  @spec validate_default_language(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_default_language(changeset) do
    default_language_id = get_field(changeset, :default_language_id)
    active_language_ids = get_field(changeset, :active_language_ids)

    check_valid_language(changeset, default_language_id, active_language_ids)
  end

  @spec check_valid_language(Ecto.Changeset.t(), non_neg_integer(), [non_neg_integer()]) ::
          Ecto.Changeset.t()
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

  @spec add_out_of_office_if_missing(Ecto.Changeset.t()) :: Ecto.Changeset.t()
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

  Implementation of id for the map protocol
  """
  @spec id(map()) :: String.t()
  def id(%{organization_id: organization_id}) do
    "org:#{organization_id}"
  end
end
