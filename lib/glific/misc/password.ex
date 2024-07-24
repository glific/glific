defmodule Glific.Password do
  @moduledoc """
  This Module creates generates a password and hashses it to automate gupshup linking
  """
  alias Pow.Ecto.Schema.Password, as: Pwd

  @lower_list ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
  @upper_list ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
  @digit_list ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  @special_list ["!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-",
                 ".", "/", ":", ";", "<", "=", ">", "?", "@", "[", "]", "^", "_", "{", "|", "}", "~"]

  @all @lower_list ++ @upper_list ++ @digit_list ++ @special_list

  require Logger

  @doc """
  "Generates a 15-character random password and hashes the generated password via Ecto module
  """
  @spec generate_password() :: String.t() | {:error, String.t()}
  def generate_password do
    generated_password = generate_password([], 15)
    hashed_password = Pwd.pbkdf2_hash(generated_password)
    Logger.info("Generated and hashed password successfully.")
    hashed_password
  end

  # Helper functions seperated into recursive and base cases to randomly generate password via recursion
  defp generate_password(password_key, 0), do: Enum.shuffle(password_key) |> Enum.join()
  defp generate_password(password_key, len), do: generate_password([Enum.random(@all) | password_key], len - 1)

end
