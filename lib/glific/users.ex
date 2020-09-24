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
    Users.User
  }

  @doc """
  Returns the list of filtered users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  @spec list_users(map()) :: [User.t()]
  def list_users(%{filter: %{organization_id: _organization_id}} = args) do
    Repo.list_filter(args, User, &Repo.opts_with_name/2, &Repo.filter_with/2)
  end

  @doc """
  Return the count of users, using the same filter as list_users
  """
  @spec count_users(map()) :: integer
  def count_users(%{filter: %{organization_id: _organization_id}} = args),
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
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%User{} = user, attrs) do
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
  def authenticate(params) do
    authenticate_user_organization(params["organization_id"], params)
  end

  defp authenticate_user_organization(nil, _params), do: nil

  defp authenticate_user_organization(organization_id, params) do
    User
    |> Repo.get_by(phone: params["phone"], organization_id: organization_id)
    |> case do
      # Prevent timing attack
      nil -> %User{password_hash: nil}
      user -> user
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
end
