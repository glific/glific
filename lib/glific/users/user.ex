defmodule Glific.Users.User do
  @moduledoc false
  use Ecto.Schema
  use Pow.Ecto.Schema, user_id_field: :phone

  alias __MODULE__

  alias Glific.{
    AccessControl.Role,
    Contacts.Contact,
    Enums.UserRoles,
    Groups.Group,
    Partners.Organization,
    Settings.Language
  }

  alias Ecto.Changeset
  import Pow.Ecto.Schema.Changeset, only: [password_changeset: 3, current_password_changeset: 3]
  import Ecto.Changeset

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          password_hash: String.t() | nil,
          fingerprint: String.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          password: String.t() | nil,
          current_password: String.t() | nil,
          password_hash: String.t() | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          roles: [String.t() | atom()] | nil,
          groups: list() | Ecto.Association.NotLoaded.t() | nil,
          is_restricted: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          last_login_at: :utc_datetime | nil,
          last_login_from: String.t() | nil,
          upload_contacts: boolean() | false,
          confirmed_at: :utc_datetime | nil
        }

  @required_fields [:phone, :name, :password, :contact_id, :organization_id]
  @optional_fields [
    :name,
    :roles,
    :is_restricted,
    :last_login_from,
    :last_login_at,
    :language_id,
    :upload_contacts,
    :confirmed_at
  ]

  schema "users" do
    field(:name, :string)
    field(:roles, {:array, UserRoles}, default: [:none])

    # is this user restricted to contacts only in groups that they are part of
    field(:is_restricted, :boolean, default: false)

    # we are lazy, so we use the fingerprint generated by pow as out unique token
    # to identify the same user from different browsers and/or machines
    field(:fingerprint, :string, virtual: true)

    field(:upload_contacts, :boolean, default: false)

    field(:last_login_from, :string, default: nil)
    field(:last_login_at, :utc_datetime)
    field(:confirmed_at, :utc_datetime)

    belongs_to(:contact, Contact)
    belongs_to(:language, Language)
    belongs_to(:organization, Organization)

    pow_user_fields()

    many_to_many(:groups, Group, join_through: "users_groups", on_replace: :delete)
    many_to_many(:access_roles, Role, join_through: "user_roles", on_replace: :delete)

    timestamps()
  end

  @doc """
  Overriding the changeset for PoW and switch phone and email. At some later point, we will
  send an SMS message to the user with a new code to change their password
  """
  @spec changeset(User.t(), map()) :: Ecto.Changeset.t()
  def changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> Changeset.cast(attrs, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
    |> glific_phone_field_changeset(attrs, @pow_config)
    |> current_password_changeset(attrs, @pow_config)
    |> password_changeset(attrs, @pow_config)
    |> Changeset.unique_constraint(:contact_id)
  end

  @doc """
  Simple changeset for phone. We will add phone validation over a period of time
  """
  @spec glific_phone_field_changeset(Ecto.Schema.t() | Changeset.t(), map(), Pow.Config.t()) ::
          Changeset.t()
  def glific_phone_field_changeset(user_or_changeset, params, _config) do
    user_or_changeset
    |> Changeset.cast(params, [:phone])
    |> Changeset.update_change(:phone, &maybe_normalize_user_id_field_value/1)
    |> Changeset.validate_required([:phone])
    |> Changeset.unique_constraint([:phone, :organization_id])
  end

  @doc """
  Simple changeset for update name, roles and is_restricted
  """
  @spec update_fields_changeset(Ecto.Schema.t() | Changeset.t(), map()) ::
          Changeset.t()
  def update_fields_changeset(user_or_changeset, params) do
    user_or_changeset
    |> Changeset.cast(params, [
      :name,
      :roles,
      :password,
      :is_restricted,
      :last_login_at,
      :last_login_from,
      :language_id
    ])
    |> Changeset.validate_required([:name, :roles])
    |> password_changeset(params, @pow_config)
    |> Changeset.unique_constraint(:contact_id)
  end

  defp maybe_normalize_user_id_field_value(value) when is_binary(value),
    do: Pow.Ecto.Schema.normalize_user_id_field_value(value)

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> changeset(attrs)
    |> validate_password(opts)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Glific.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 72)
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:phone])
    |> case do
      %{changes: %{phone: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :phone, "did not change")
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Pbkdf2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Glific.Users.User{password_hash: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset_v2(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end
end
