defmodule Glific.Users do
  @moduledoc """
  The Users context.
  """
  import Ecto.Query, warn: false

  alias Glific.{Users.User, Repo, Search.Full}

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  @spec list_users(map()) :: [User.t()]
  def list_users(args \\ %{}) do
    User
    |> Repo.all()
  end

  @doc """
  Return the count of users, using the same filter as list_users
  """
  @spec count_users(map()) :: integer
  def count_users(args \\ %{}) do
    User
    |> Repo.aggregate(:count)
  end

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
end
