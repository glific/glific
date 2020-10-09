defmodule Glific.Users.User do
  @moduledoc false
  use Ecto.Schema
  use Pow.Ecto.Schema, user_id_field: :phone

  alias Glific.{
    Contacts.Contact,
    Enums.UserRoles,
    Groups.Group,
    Partners.Organization
  }

  alias Ecto.Changeset
  import Pow.Ecto.Schema.Changeset, only: [password_changeset: 3, current_password_changeset: 3]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          phone: String.t() | nil,
          password_hash: String.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [:phone, :name, :password, :contact_id, :organization_id]
  @optional_fields [:name, :roles]
  # keeping the order alphabetical ASC for frontend dropdown display
  @user_roles ~w(Admin Manager None Staff)

  schema "users" do
    field :name, :string
    field :roles, {:array, UserRoles}, default: [:none]

    belongs_to :contact, Contact
    belongs_to :organization, Organization

    pow_user_fields()

    many_to_many :groups, Group, join_through: "users_groups", on_replace: :delete

    timestamps()
  end

  @doc """
  A constant function to get list of roles
  """
  def get_roles_list do
    @user_roles
  end

  @doc """
  Overriding the changeset for PoW and switch phone and email. At some later point, we will
  send an SMS message to the user with a new code to change their password
  """
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
  Simple changeset for update name and roles
  """
  @spec update_fields_changeset(Ecto.Schema.t() | Changeset.t(), map()) ::
          Changeset.t()
  def update_fields_changeset(user_or_changeset, params) do
    user_or_changeset
    |> Changeset.cast(params, [:name, :roles, :password])
    |> Changeset.validate_required([:name, :roles])
    |> password_changeset(params, @pow_config)
    |> Changeset.unique_constraint(:contact_id)
  end

  defp maybe_normalize_user_id_field_value(value) when is_binary(value),
    do: Pow.Ecto.Schema.normalize_user_id_field_value(value)
end
