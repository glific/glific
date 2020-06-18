defmodule PasswordlessAuth.VerificationCode do
  @moduledoc false
  # https://github.com/madebymany/passwordless_auth

  @enforce_keys [:code, :expires]
  defstruct attempts: 0, attempts_blocked_until: nil, code: nil, expires: nil

  @type t :: %__MODULE__{
          attempts: integer(),
          attempts_blocked_until: NaiveDateTime.t() | nil,
          code: integer(),
          expires: NaiveDateTime.t()
        }

  @doc false
  @spec generate_code(integer()) :: String.t()
  def generate_code(code_length) do
    for _ <- 1..code_length do
      :rand.uniform(10) - 1
    end
    |> Enum.join()
  end
end
