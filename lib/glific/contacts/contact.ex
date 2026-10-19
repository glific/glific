defmodule Glific.Contacts.Contact do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.ContactProviderStatus,
    Enums.ContactStatus,
    Groups.Group,
    Groups.WAGroup,
    Partners.Organization,
    Profiles.Profile,
    Settings.Language,
    Tags.Tag,
    Users.User
  }

  @required_fields [
    :language_id,
    :organization_id
  ]
  @optional_fields [
    :phone,
    :name,
    :contact_type,
    :status,
    :is_org_read,
    :is_org_replied,
    :is_contact_replied,
    :first_message_number,
    :last_message_number,
    :last_communication_at,
    :settings,
    :fields,
    :active_profile_id
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          masked_phone: String.t() | nil,
          contact_type: String.t() | nil,
          status: ContactStatus.t() | nil,
          is_org_read: boolean,
          is_org_replied: boolean,
          is_contact_replied: boolean,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          identities: [ContactIdentity.t()] | Ecto.Association.NotLoaded.t(),
          whatsapp_identity: ContactIdentity.t() | Ecto.Association.NotLoaded.t() | nil,
          active_profile: Profile.t() | Ecto.Association.NotLoaded.t() | nil,
          active_profile_id: non_neg_integer | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          first_message_number: integer,
          last_message_number: integer,
          last_communication_at: :utc_datetime | nil,
          settings: map() | nil,
          fields: map() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "contacts" do
    field(:name, :string)
    field(:phone, :string)
    field(:masked_phone, :string, virtual: true)
    field(:contact_type, :string, default: "WABA")

    field(:status, ContactStatus)

    # The pre-identity copy of the WhatsApp state: nothing writes it, and only
    # `Glific.Contacts.WhatsAppState` reads it, for a contact with no WhatsApp identity row yet.
    field(:legacy_optin_time, :utc_datetime, source: :optin_time, read_after_writes: true)
    field(:legacy_optin_status, :boolean, source: :optin_status, read_after_writes: true)
    field(:legacy_optin_method, :string, source: :optin_method, read_after_writes: true)
    field(:legacy_optout_time, :utc_datetime, source: :optout_time, read_after_writes: true)
    field(:legacy_optout_method, :string, source: :optout_method, read_after_writes: true)
    field(:legacy_bsp_status, ContactProviderStatus, source: :bsp_status, read_after_writes: true)

    field(:legacy_last_message_at, :utc_datetime,
      source: :last_message_at,
      read_after_writes: true
    )

    field(:is_org_read, :boolean, default: true)
    field(:is_org_replied, :boolean, default: true)
    field(:is_contact_replied, :boolean, default: true)

    field(:first_message_number, :integer, default: 1)
    field(:last_message_number, :integer, default: 0)

    field(:last_communication_at, :utc_datetime)

    field(:settings, :map, default: %{})
    field(:fields, :map, default: %{})

    belongs_to(:language, Language)
    belongs_to(:active_profile, Profile)
    belongs_to(:organization, Organization)

    has_one(:user, User)
    has_many(:identities, ContactIdentity)
    has_one(:whatsapp_identity, ContactIdentity, where: [channel: :whatsapp])
    many_to_many(:tags, Tag, join_through: "contacts_tags", on_replace: :delete)

    many_to_many(:groups, Group, join_through: "contacts_groups", on_replace: :delete)
    many_to_many(:wa_groups, WAGroup, join_through: "contacts_wa_groups", on_replace: :delete)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types. A new WhatsApp contact must have a phone;
  a new contact on the web channel needn't.
  """
  @spec changeset(Contact.t(), map(), :whatsapp | :web) :: Ecto.Changeset.t()
  def changeset(contact, attrs, channel \\ :whatsapp) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_phone_on_insert(channel)
    |> validate_phone_removal()
    |> validate_fields_map()
    |> unique_constraint([:phone, :organization_id])
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:active_profile_id)
  end

  @spec validate_phone_on_insert(Ecto.Changeset.t(), :whatsapp | :web) :: Ecto.Changeset.t()
  defp validate_phone_on_insert(%{data: %{__meta__: %{state: :built}}} = changeset, :whatsapp),
    do: validate_required(changeset, [:phone])

  defp validate_phone_on_insert(changeset, _channel), do: changeset

  @doc false
  @spec to_minimal_map(Contact.t()) :: map()
  def to_minimal_map(contact) do
    Map.take(contact, [:id | @required_fields ++ @optional_fields])
  end

  @doc """
  Populate virtual field of masked phone number
  """
  @spec populate_masked_phone(Contact.t()) :: Contact.t()
  def populate_masked_phone(%Contact{phone: phone} = contact) when phone in [nil, ""],
    do: %{contact | masked_phone: nil}

  def populate_masked_phone(%Contact{phone: phone} = contact) do
    masked_phone =
      "#{elem(String.split_at(phone, 4), 0)}******#{elem(String.split_at(phone, -2), 1)}"

    %{contact | masked_phone: masked_phone}
  end

  @spec validate_phone_removal(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_phone_removal(%{data: %{phone: phone}} = changeset) when phone not in [nil, ""] do
    case fetch_change(changeset, :phone) do
      {:ok, new_phone} when new_phone in [nil, ""] ->
        add_error(changeset, :phone, "can't be removed once set")

      _no_removal ->
        changeset
    end
  end

  defp validate_phone_removal(changeset), do: changeset

  @spec validate_fields_map(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_fields_map(%{changes: %{fields: fields}} = changeset) do
    fields
    |> Enum.reduce_while(changeset, fn {_field, value}, _result ->
      case validate_field_value(value) do
        :ok ->
          {:cont, changeset}

        {:error, err} ->
          {:halt,
           add_error(
             changeset,
             :fields,
             err
           )}
      end
    end)
  end

  defp validate_fields_map(changeset), do: changeset

  @spec validate_field_value(map()) :: :ok | {:error, String.t()}
  defp validate_field_value(%{} = value) do
    Enum.reduce_while(value, :ok, fn {field, value}, _result ->
      case {field, value} do
        {:inserted_at, %DateTime{} = _value} ->
          {:cont, :ok}

        {:inserted_at, _value} ->
          {:halt, {:error, "Expected value of #{field} to be of type DateTime.t()"}}

        {_, _value} ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_field_value(_value), do: {:error, "value should be a map"}
end
