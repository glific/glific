defmodule Glific.Users do
  @moduledoc """
  The Users context.
  """

  use Pow.Ecto.Context,
    repo: Glific.Repo,
    user: Glific.Users.User

  import Ecto.Query, warn: false

  alias Glific.{
    Repo,
    Settings.Language,
    Users.User
  }

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
  # nil (and treat it as not being updated), since we dont update these values
  @spec is_updated?(any, any) :: boolean
  defp is_updated?(_original, nil = _new), do: false
  defp is_updated?(original, new), do: original != new

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
    # lets invalidate the tokens and socket for this user
    # we do this ONLY if either the role or is_restricted has changed
    if is_updated?(user.roles, attrs[:roles]) ||
         is_updated?(user.is_restricted, attrs[:is_restricted]) do
      GlificWeb.APIAuthPlug.delete_all_user_sessions(@pow_config, user)
    end

    user
    |> User.update_fields_changeset(attrs)
    |> Repo.update()
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
    GlificWeb.APIAuthPlug.delete_all_user_sessions(@pow_config, user)

    Repo.delete(user)
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

  defp authenticate_user_organization(organization_id, params) do
    User
    |> Repo.get_by(phone: params["phone"], organization_id: organization_id)
    |> case do
      # Prevent timing attack
      nil ->
        %User{password_hash: nil}

      user -> user |> Repo.preload(:language)
    end
    |> verify_password(params["password"])
  end

  @spec verify_password(User.t(), String.t()) :: User.t() | nil
  defp verify_password(user, password),
    do:
      if(User.verify_password(user, password),
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
    {:ok, user} = update_user(user, %{roles: [:admin]})
    user
  end

  defp maybe_promote_user(_list, user), do: user
end
