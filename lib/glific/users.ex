defmodule Glific.Users do
  @moduledoc """
  The Users context.
  """

  use Pow.Ecto.Context,
    repo: Glific.Repo,
    user: Glific.Users.User

  import Ecto.Query, warn: false

  alias Glific.{
    AccessControl.Role,
    AccessControl.UserRole,
    Repo,
    Settings.Language,
    Users.User
  }

  require Logger

  @doc """
  Returns the list of filtered users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  @spec list_users(map()) :: [User.t()]
  def list_users(args) do
    Repo.list_filter(args, User, &Repo.opts_with_name/2, &Repo.filter_with/2)
  end

  @doc """
  Return the count of users, using the same filter as list_users
  """
  @spec count_users(map()) :: integer
  def count_users(args),
    do: Repo.count_filter(args, User, &Repo.filter_with/2)

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(integer) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    attrs =
      attrs
      |> Glific.atomize_keys()
      |> get_default_language()

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_default_language(map()) :: map()
  defp get_default_language(attrs) do
    {:ok, en} = Repo.fetch_by(Language, %{label_locale: "English"})
    attrs |> Map.merge(%{language_id: en.id})
  end

  # special type of comparison to allow for nils, we permit comparing with
  # nil (and treat it as not being updated), since we don't update these values
  @spec updated?(any, any) :: boolean
  defp updated?(_original, nil = _new), do: false
  defp updated?(original, new), do: original != new

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @pow_config [otp_app: :glific]
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%User{} = user, attrs) do
    attrs =
      attrs
      |> validate_add_role_ids?()
      |> check_access_role(attrs)

    # lets invalidate the tokens and socket for this user
    # we do this ONLY if either the role or is_restricted has changed
    if validate_add_role_ids?(attrs) ||
         updated?(user.is_restricted, attrs[:is_restricted]) ||
         validate_delete_role_ids?(attrs) do
      GlificWeb.APIAuthPlug.delete_all_user_sessions(@pow_config, user)
    end

    with {:ok, updated_user} <-
           user
           |> User.update_fields_changeset(attrs)
           |> Repo.update() do
      if Map.has_key?(attrs, :add_role_ids),
        do: update_user_roles(attrs, updated_user),
        else: {:ok, updated_user}
    end
  end

  @spec validate_add_role_ids?(map()) :: boolean()
  defp validate_add_role_ids?(%{add_role_ids: add_role_ids} = _attrs),
    do: length(add_role_ids) != 0

  defp validate_add_role_ids?(_attrs), do: false

  @spec validate_delete_role_ids?(map()) :: boolean()
  defp validate_delete_role_ids?(%{delete_role_ids: delete_role_ids} = _attrs),
    do: length(delete_role_ids) != 0

  defp validate_delete_role_ids?(_attrs), do: false

  @spec check_access_role(boolean(), map()) :: map()
  defp check_access_role(false, attrs), do: attrs

  defp check_access_role(true, %{add_role_ids: add_role_ids} = attrs) do
    roles =
      Role
      |> select([r], r.label)
      |> where([r], r.id in ^add_role_ids)
      |> Repo.all()

    role =
      cond do
        Enum.any?(roles, fn role -> role == "Admin" end) -> ["admin"]
        Enum.any?(roles, fn role -> role == "Manager" end) -> ["manager"]
        Enum.any?(roles, fn role -> role == "Staff" end) -> ["staff"]
        Enum.any?(roles, fn role -> role == "No access" end) -> ["none"]
        Enum.any?(roles, fn role -> role == "Glific Admin" end) -> ["glific_admin"]
        true -> ["manager"]
      end

    Map.put(attrs, :roles, role)
  end

  @spec update_user_roles(map(), User.t()) :: {:ok, User.t()}
  defp update_user_roles(attrs, user) do
    %{access_controls: access_controls} =
      attrs
      |> Map.put(:user_id, user.id)
      |> UserRole.update_user_roles()

    user
    |> Map.put(:access_roles, access_controls)
    |> then(&{:ok, &1})
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{} = user) do
    # lets invalidate the tokens and socket for this user
    current_user = Repo.get_current_user()

    Logger.info(
      "Deleting user from org_id: #{user.organization_id} user_id: #{user.id} name: #{user.name} phone: #{user.phone} by #{current_user.name}"
    )

    GlificWeb.APIAuthPlug.delete_all_user_sessions(@pow_config, user)

    Repo.delete(user)
  end

  @doc """
  Fetches active session for user

  ## Examples

      iex> fetch_user_session(user)
      1

  """
  @spec fetch_user_session(User.t()) :: integer()
  def fetch_user_session(%User{} = user) do
    GlificWeb.APIAuthPlug.fetch_all_user_sessions(@pow_config, user)
  end

  @doc """
  Reset user password
  """
  @spec reset_user_password(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def reset_user_password(%User{} = user, attrs) do
    user
    |> User.update_fields_changeset(attrs)
    |> Repo.update()
  end

  @impl true
  @spec authenticate(map()) :: User.t() | nil
  def authenticate(params) do
    authenticate_user_organization(params["organization_id"], params)
  end

  @spec authenticate_user_organization(non_neg_integer | nil, map()) :: User.t() | nil
  defp authenticate_user_organization(nil, _params), do: nil

  defp authenticate_user_organization(
         organization_id,
         %{"phone" => phone, "password" => password}
       ) do
    User
    |> Repo.get_by(phone: phone, organization_id: organization_id)
    |> case do
      # Prevent timing attack
      nil ->
        %User{password_hash: nil}

      user ->
        user |> Repo.preload(:language)
    end
    |> verify_password(password)
  end

  defp authenticate_user_organization(_organization_id, _params), do: nil

  @spec verify_password(User.t(), String.t()) :: User.t() | nil
  defp verify_password(user, password),
    do:
      if(User.valid_password?(user, password),
        do: user,
        else: nil
      )

  @doc """
  Promote the first user of the system to admin automatically.
  Ignore NGO or SaaS users which are automatically created
  """
  @spec promote_first_user(User.t()) :: User.t()
  def promote_first_user(user) do
    User
    |> where([u], u.id != ^user.id)
    |> where([u], not ilike(u.name, "NGO %"))
    |> where([u], not ilike(u.name, "SaaS %"))
    |> select([u], [u.id])
    |> Repo.all()
    |> maybe_promote_user(user)
  end

  @spec maybe_promote_user(list(), User.t()) :: User.t()
  defp maybe_promote_user([], user) do
    # this is the first user, since the list of valid org users is empty
    {:ok, user} =
      update_user(user, %{
        roles: [:admin],
        add_role_ids: get_role_id("Admin"),
        organization_id: user.organization_id
      })

    user
  end

  defp maybe_promote_user(_list, user) do
    {:ok, user} =
      update_user(user, %{
        roles: [:none],
        add_role_ids: get_role_id("No access"),
        organization_id: user.organization_id
      })

    user
  end

  @spec get_role_id(String.t()) :: list()
  defp get_role_id(role) do
    Role
    |> select([r], r.id)
    |> where([r], ilike(r.label, ^role))
    |> Repo.all()
  end
end
