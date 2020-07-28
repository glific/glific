defmodule Glific.Users do
  @moduledoc """
  The Users context.
  """
  import Ecto.Query, warn: false

  alias Glific.Repo
  alias Glific.Users.User

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
    with false <- is_nil(attrs[:password]) || is_nil(attrs[:otp]),
         :ok <- PasswordlessAuth.verify_code(user.phone, attrs.otp) do
      PasswordlessAuth.remove_code(user.phone)
      attrs = Map.merge(attrs, %{password_confirmation: attrs.password})

      user
      |> User.update_fields_changeset(attrs)
      |> User.reset_password_changeset(attrs)
      |> Repo.update()
    else
      true ->
        user
        |> User.update_fields_changeset(attrs)
        |> Repo.update()

      {:error, error} ->
        {:error, Atom.to_string(error)}
    end
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
    |> User.reset_password_changeset(attrs)
    |> Repo.update()
  end
end
