defmodule Glific.Users do
  @moduledoc """
  The Users context.
  """
  import Ecto.Query, warn: false

  alias Glific.{Groups, Repo, Users.User}

  @doc """
  Returns the list of filtered users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  @spec list_users(map()) :: [User.t()]
  def list_users(args \\ %{}),
    do: Repo.list_filter(args, User, &Repo.opts_with_name/2, &Repo.filter_with/2)

  @doc """
  Return the count of users, using the same filter as list_users
  """
  @spec count_users(map()) :: integer
  def count_users(args \\ %{}),
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
  @spec create_user(map()) :: %User{}
  def create_user(attrs \\ %{}) do
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
    {:ok, user} =
      user
      |> User.update_fields_changeset(attrs)
      |> Repo.update()

    Groups.update_user_groups(%{user_id: user.id, group_ids: attrs[:group_ids]})

    ### Need to make a query again to load and cast the roles.
    ### We will figure out a way and clean this in the future.
    {:ok, get_user!(user.id)}
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
end
