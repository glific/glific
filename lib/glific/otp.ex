defmodule Glific.OTP do
  @moduledoc """
  Purpose-scoped wrapper around `PasswordlessAuth`.

  `PasswordlessAuth` keeps one global map keyed by the recipient string alone, so a bare phone
  number lets a code minted by one flow satisfy an unrelated one — the trial signup flow mails a
  code to a self-declared address, which would otherwise be accepted by the password reset flow
  for the same phone. Storing every code under a `<scope>:<phone>` key confines it to the flow
  that minted it.

  All OTP generation and verification goes through this module; do not call `PasswordlessAuth`
  directly.
  """

  @typedoc """
  The flow an OTP belongs to. A code is only ever verifiable by the scope that generated it.

  * `:auth` — codes delivered over WhatsApp to the contact's own phone (registration, password
    reset, password change).
  * `:trial` — codes emailed to the address supplied in a trial signup request.
  """
  @type scope :: :auth | :trial

  @scopes [:auth, :trial]

  @doc "Generates and stores an OTP for the given phone under the given scope."
  @spec generate_code(scope(), String.t()) :: String.t()
  def generate_code(scope, phone) when scope in @scopes,
    do: PasswordlessAuth.generate_code(key(scope, phone))

  @doc "Verifies an OTP against the given scope, consuming the code once it matches."
  @spec verify_code(scope(), String.t(), String.t()) ::
          :ok | {:error, :attempt_blocked | :code_expired | :does_not_exist | :incorrect_code}
  def verify_code(scope, phone, attempt_code) when scope in @scopes do
    key = key(scope, phone)

    with :ok <- PasswordlessAuth.verify_code(key, attempt_code) do
      PasswordlessAuth.remove_code(key)
      :ok
    end
  end

  @spec key(scope(), String.t()) :: String.t()
  defp key(scope, phone), do: "#{scope}:#{phone}"
end
