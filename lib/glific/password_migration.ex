defmodule Glific.PasswordMigration do
  @moduledoc """
  Convert all the previous password hashes to newly encoded password which are compatible with both auth libraries.
  We will remove this migration soon or may be move this file to priv migration directory
  """

  import Ecto.Query, warn: false

  alias Glific.Repo
  alias Glific.Users.User
  alias Pbkdf2.Base64

  @doc false
  @spec fix_password(non_neg_integer(), boolean()) :: any()
  def fix_password(user_id, reverse \\ false) do
    user = Repo.get!(User, user_id, skip_organization_id: true)
    new_hash = convert_hash_to_new_auth(user.password_hash, reverse)

    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(set: [password_hash: new_hash])
  end

  @doc false
  @spec convert_hash_to_new_auth(String.t(), boolean()) :: any()
  def convert_hash_to_new_auth(current_hash, reverse \\ false) do
    [digest, iterations, salt, hash] = decode(current_hash)

    if reverse == true do
      old_encode(digest, iterations, salt, hash)
    else
      encode(digest, iterations, salt, hash)
    end
  end

  defp encode(digest, iterations, salt, hash) do
    salt = Base64.encode(salt)
    hash = Base64.encode(hash)

    "$pbkdf2-#{digest}$#{iterations}$#{salt}$#{hash}"
  end

  defp old_encode(digest, iterations, salt, hash) do
    salt = Base.encode64(salt)
    hash = Base.encode64(hash)

    "$pbkdf2-#{digest}$#{iterations}$#{salt}$#{hash}"
  end

  @doc false
  @spec decode(String.t()) :: any()
  def decode(hash) do
    case String.split(hash, "$", trim: true) do
      ["pbkdf2-" <> digest, iterations, salt, hash] ->
        {:ok, salt} = Base.decode64(salt)
        {:ok, hash} = Base.decode64(hash)
        digest = String.to_existing_atom(digest)
        iterations = String.to_integer(iterations)

        [digest, iterations, salt, hash]

      _ ->
        raise_not_valid_password_hash!()
    end
  end

  @spec raise_not_valid_password_hash!() :: no_return()
  defp raise_not_valid_password_hash!,
    do: raise(ArgumentError, "not a valid encoded password hash")
end
