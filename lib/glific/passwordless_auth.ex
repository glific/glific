defmodule PasswordlessAuth do
  @moduledoc """
  https://github.com/madebymany/passwordless_auth
  PasswordlessAuth is a library gives you the ability to verify a user's
  phone number by sending them a verification code, and verifying that
  the code they provide matches the code that was sent to their phone number.

  Verification codes are stored in an Agent along with the phone number they
  were sent to. They are stored with an expiration date/time.

  A garbage collector removes expires verification codes from the store.
  See PasswordlessAuth.GarbageCollector
  """
  use Application
  alias PasswordlessAuth.{GarbageCollector, VerificationCode, Store}

  @default_verification_code_ttl 300
  @default_num_attempts_before_timeout 5
  @default_rate_limit_timeout_length 60
  @twilio_adapter Application.get_env(:passwordless_auth, :twilio_adapter) || ExTwilio

  @type verification_failed_reason() ::
          :attempt_blocked | :code_expired | :does_not_exist | :incorrect_code

  @doc false
  def start(_type, _args) do
    children = [
      GarbageCollector,
      Store
    ]

    opts = [strategy: :one_for_one, name: PasswordlessAuth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Send an SMS with a verification code to the given `phone_number`

  The verification code is valid for the number of seconds given to the
  `verification_code_ttl` config option (defaults to 300)

  Options for the Twilio request can be passed to `opts[:twilio_request_options`.
  You'll need to pass at least a `from` or `messaging_service_sid` option
  to `options[:twilio_request_options]` for messages to be sent
  (see the [Twilio API documentation](https://www.twilio.com/docs/api/messaging/send-messages#conditional-parameters))
  For example:

  Arguments:

  - `phone_number`: The phone number that will receive the text message
  - `opts`: Options (see below)

  Options:

  - `message`: A custom text message template. The verification code
  can be injected with this formatting: _"Yarrr, {{code}} be the secret"_.
  Defaults to _"Your verification code is: {{code}}"_
  - `code_length`: Length of the verification code (defaults to 6)
  - `twilio_request_options`: A map of options that are passed to the Twilio request
  (see the [Twilio API documentation](https://www.twilio.com/docs/api/messaging/send-messages#conditional-parameters))

  Returns `{:ok, twilio_response}` or `{:error, error}`.
  """
  @spec create_and_send_verification_code(String.t(), list()) ::
          {:ok, map()} | {:error, String.t()}
  def create_and_send_verification_code(phone_number, opts \\ []) do
    message = opts[:message] || "Your verification code is: {{code}}"
    code_length = opts[:code_length] || 6
    code = VerificationCode.generate_code(code_length)

    ttl =
      Application.get_env(:passwordless_auth, :verification_code_ttl) ||
        @default_verification_code_ttl

    expires = NaiveDateTime.utc_now() |> NaiveDateTime.add(ttl)

    twilio_request_options = opts[:twilio_request_options] || []

    {:ok, code}

    # Would use gupshup instead of twilio

    # request =
    #   Enum.into(twilio_request_options, %{
    #     to: phone_number,
    #     body: String.replace(message, "{{code}}", code)
    #   })

    # case @twilio_adapter.Message.create(request) do
    #   {:ok, response} ->
    #     Agent.update(
    #       Store,
    #       &Map.put(&1, phone_number, %VerificationCode{
    #         code: code,
    #         expires: expires
    #       })
    #     )

    #     {:ok, response}

    #   {:error, message, _code} ->
    #     {:error, message}
    # end
  end

  @doc """
  Verifies that a the given `phone_number` has the
  given `verification_code` stores in state and that
  the verification code hasn't expired.

  Returns `:ok` or `{:error, :reason}`.

  ## Examples

      iex> PasswordlessAuth.verify_code("+447123456789", "123456")
      {:error, :does_not_exist}

  """
  @spec verify_code(String.t(), String.t()) :: :ok | {:error, verification_failed_reason()}
  def verify_code(phone_number, attempt_code) do
    state = Agent.get(Store, fn state -> state end)

    with :ok <- check_code_exists(state, phone_number),
         verification_code <- Map.get(state, phone_number),
         :ok <- check_verification_code_not_expired(verification_code),
         :ok <- check_attempt_is_allowed(verification_code),
         :ok <- check_attempt_code(verification_code, attempt_code) do
      reset_attempts(phone_number)
      :ok
    else
      {:error, :incorrect_code} = error ->
        increment_or_block_attempts(phone_number)
        error

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Removes a code from state based on the given `phone_number`

  Returns `{:ok, %VerificationCode{...}}` or `{:error, :reason}`.
  """
  @spec remove_code(String.t()) :: {:ok, VerificationCode.t()} | {:error, :does_not_exist}
  def remove_code(phone_number) do
    state = Agent.get(Store, fn state -> state end)

    with :ok <- check_code_exists(state, phone_number) do
      code = Agent.get(Store, &Map.get(&1, phone_number))
      Agent.update(Store, &Map.delete(&1, phone_number))
      {:ok, code}
    end
  end

  @spec check_code_exists(map(), String.t()) :: :ok | {:error, :does_not_exist}
  defp check_code_exists(state, phone_number) do
    if Map.has_key?(state, phone_number) do
      :ok
    else
      {:error, :does_not_exist}
    end
  end

  @spec check_verification_code_not_expired(VerificationCode.t()) :: :ok | {:error, :code_expired}
  defp check_verification_code_not_expired(%VerificationCode{expires: expires}) do
    case NaiveDateTime.compare(expires, NaiveDateTime.utc_now()) do
      :gt -> :ok
      _ -> {:error, :code_expired}
    end
  end

  @spec check_attempt_is_allowed(VerificationCode.t()) :: :ok | {:error, :attempt_blocked}
  defp check_attempt_is_allowed(%VerificationCode{attempts_blocked_until: nil}), do: :ok

  defp check_attempt_is_allowed(%VerificationCode{attempts_blocked_until: attempts_blocked_until}) do
    case NaiveDateTime.compare(attempts_blocked_until, NaiveDateTime.utc_now()) do
      :lt -> :ok
      _ -> {:error, :attempt_blocked}
    end
  end

  @spec check_attempt_code(VerificationCode.t(), String.t()) :: :ok | {:error, :incorrect_code}
  defp check_attempt_code(%VerificationCode{code: code}, attempt_code) do
    if attempt_code == code do
      :ok
    else
      {:error, :incorrect_code}
    end
  end

  @spec reset_attempts(String.t()) :: :ok
  defp reset_attempts(phone_number) do
    Agent.update(Store, &put_in(&1, [phone_number, Access.key(:attempts)], 0))
  end

  @spec increment_or_block_attempts(String.t()) :: :ok
  defp increment_or_block_attempts(phone_number) do
    num_attempts_before_timeout =
      Application.get_env(:passwordless_auth, :num_attempts_before_timeout) ||
        @default_num_attempts_before_timeout

    attempts = Agent.get(Store, &get_in(&1, [phone_number, Access.key(:attempts)]))

    if attempts < num_attempts_before_timeout - 1 do
      Agent.update(Store, &put_in(&1, [phone_number, Access.key(:attempts)], attempts + 1))
    else
      num_attempts_before_timeout =
        Application.get_env(:passwordless_auth, :rate_limit_timeout_length) ||
          @default_rate_limit_timeout_length

      attempts_blocked_until =
        NaiveDateTime.utc_now() |> NaiveDateTime.add(num_attempts_before_timeout)

      Agent.update(Store, fn state ->
        state
        |> put_in([phone_number, Access.key(:attempts)], 0)
        |> put_in([phone_number, Access.key(:attempts_blocked_until)], attempts_blocked_until)
      end)
    end
  end
end
