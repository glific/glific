defmodule GlificWeb.API.V1.WebChannelAuthController do
  @moduledoc """
  Public, unauthenticated endpoints that let a browser-based beneficiary request and verify a
  one-time code delivered over WhatsApp, so they can sign in to the web channel widget.

  This authenticates a `Glific.Contacts.Contact`, never a `Glific.Users.User` — it is
  deliberately distinct from the Pow staff registration flow in
  `GlificWeb.API.V1.RegistrationController`. The code travels over WhatsApp rather than SMS
  because SMS delivery is not enabled yet (see #5659's Phase-0 -> Phase-1 rollout table).

  ## Interim behaviour: opt-in is implied, not asked for

  `request_otp/2` opts the contact in to WhatsApp (`Contacts.contact_opted_in/4` writes
  `optin_status: true` and an `optin_time`) purely because someone typed a phone number into a
  login box. That is how the staff registration flow has always worked, and it is what makes the
  OTP deliverable at all — an HSM cannot be sent to a contact who is not opted in. It is still
  weaker than consent: the beneficiary is never asked.

  US3 of #5659 replaces this with an explicit, unchecked-by-default consent step at the OTP
  screen, recorded with a timestamp, and is deliberately not in this ticket. Until it ships,
  treat an `optin_method` of `"web_channel"` as *implied* consent and do not read it as the
  beneficiary having agreed to anything.
  """

  use GlificWeb, :controller

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flags,
    Messages,
    OTP,
    Partners,
    Repo,
    SafeLog
  }

  alias GlificWeb.WebChannel.{DisplayName, Token}
  alias Plug.Conn

  # Neutral response returned regardless of whether `phone` belongs to a known contact or
  # whether delivery succeeded, so the API never discloses which numbers are contacts of this
  # organization (account/number enumeration protection).
  @request_otp_message "If this number is registered on WhatsApp, you will receive a one-time code"

  @doc """
  Requests that an OTP be sent over WhatsApp to `phone`, so a beneficiary can sign in to the
  web channel widget. Always responds 200, whether or not `phone` belongs to a known contact
  and whether or not delivery actually succeeds.
  """
  @spec request_otp(Conn.t(), map()) :: Conn.t()
  def request_otp(conn, %{"phone" => phone}) when is_binary(phone) and phone != "" do
    organization_id = conn.assigns[:organization_id]

    if web_channel_enabled?(organization_id) do
      case Contacts.parse_phone_number(phone) do
        {:ok, normalized} -> request_otp_for(conn, organization_id, normalized)
        {:error, message} -> unprocessable_entity_error(conn, message)
      end
    else
      web_channel_disabled_error(conn)
    end
  end

  def request_otp(conn, _params),
    do: unprocessable_entity_error(conn, "Phone number is required")

  @spec request_otp_for(Conn.t(), non_neg_integer(), String.t()) :: Conn.t()
  defp request_otp_for(conn, organization_id, normalized) do
    case check_rate_limit(conn) do
      :ok ->
        send_web_channel_otp(organization_id, normalized)
        json(conn, %{data: %{phone: normalized, message: @request_otp_message}})

      {:error, message} ->
        conn
        |> put_status(429)
        |> json(%{error: %{status: 429, message: message}})
    end
  end

  @doc """
  Verifies an OTP minted by `request_otp/2` and, on success, signs the beneficiary in by
  returning a web channel socket token for their contact.
  """
  @spec verify_otp(Conn.t(), map()) :: Conn.t()
  def verify_otp(conn, %{"phone" => phone, "otp" => otp})
      when is_binary(phone) and phone != "" and is_binary(otp) and otp != "" do
    organization_id = conn.assigns[:organization_id]

    if web_channel_enabled?(organization_id) do
      case Contacts.parse_phone_number(phone) do
        {:ok, normalized} -> verify_otp_for(conn, organization_id, normalized, otp)
        {:error, message} -> unprocessable_entity_error(conn, message)
      end
    else
      web_channel_disabled_error(conn)
    end
  end

  def verify_otp(conn, _params),
    do: unprocessable_entity_error(conn, "Phone number and OTP are required")

  @spec verify_otp_for(Conn.t(), non_neg_integer(), String.t(), String.t()) :: Conn.t()
  defp verify_otp_for(conn, organization_id, normalized, otp) do
    case OTP.verify_code(:web_channel, normalized, otp) do
      :ok ->
        build_context(organization_id)
        resolve_contact_and_sign_in(conn, organization_id, normalized)

      # :incorrect_code | :code_expired | :does_not_exist | :attempt_blocked all collapse to
      # the same response — distinguishing them would tell an attacker whether a code was ever
      # issued for this number.
      {:error, _reason} ->
        invalid_otp_error(conn)
    end
  end

  # `OTP.verify_code/3` consumes the code the moment it matches, so by the time we get here the
  # caller has spent it and cannot retry with the same one. A `{:ok, contact} = ...` match would
  # turn any changeset failure into an unhandled 500 and strand them behind the 30s throttle —
  # `Contacts.contact_opted_in/4` can genuinely fail, e.g. two concurrent verifies for a phone
  # with no contact yet both see `nil` and race on the (phone, organization_id) unique index.
  @spec resolve_contact_and_sign_in(Conn.t(), non_neg_integer(), String.t()) :: Conn.t()
  defp resolve_contact_and_sign_in(conn, organization_id, normalized) do
    case optin_contact(organization_id, normalized) do
      {:ok, contact} ->
        json(conn, %{
          data: %{
            token: Token.sign_contact_token(contact),
            contact_id: contact.id,
            name: DisplayName.resolve(contact),
            phone: normalized
          }
        })

      {:error, error} ->
        Glific.log_error(
          "Verified a web channel OTP but could not resolve the contact for #{normalized}: " <>
            SafeLog.safe_inspect(error)
        )

        conn
        |> put_status(500)
        |> json(%{
          error: %{status: 500, message: "Could not complete sign in. Please request a new code."}
        })
    end
  end

  # Read the flag live rather than off `organization.web_channel_enabled`. That field is virtual
  # and is only stamped onto the organization struct by `Flags.set_flag_enabled/2` while
  # `Partners.fill_cache/1` runs — so the cached struct holds a *snapshot* taken whenever the
  # cache was last filled, and the org cache has a 24 hour TTL. Enabling the flag for an
  # organization does not refill it, so a controller reading the virtual field keeps answering
  # 404 long after an admin has switched the channel on. `Flags.get_flag_enabled/2` goes to
  # FunWithFlags, whose own cache is busted across nodes on write via PhoenixPubSub
  # (config.exs:196-199), so a toggle takes effect immediately.
  @spec web_channel_enabled?(non_neg_integer()) :: boolean()
  defp web_channel_enabled?(organization_id) do
    organization = Partners.organization(organization_id)
    Flags.get_flag_enabled(:web_channel_enabled, organization)
  end

  # Allow at most `count` OTP requests per client IP within `scale_ms` (default: one per 30s).
  # Keyed separately from the staff `send_otp:` limiter (registration_controller.ex) so the web
  # channel never shares a rate-limit budget with staff registration.
  @spec check_rate_limit(Conn.t()) :: :ok | {:error, String.t()}
  defp check_rate_limit(conn) do
    config = Application.get_env(:glific, :web_channel_otp_rate_limit, [])
    scale_ms = Keyword.get(config, :scale_ms, 30_000)
    count = Keyword.get(config, :count, 1)
    key = "web_channel_send_otp:#{GlificWeb.Tenants.remote_ip(conn)}"

    case ExRated.check_rate(key, scale_ms, count) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, "An OTP was just sent. Please try again in 30 seconds."}
    end
  end

  # We need to give the process permission (a root user) so the org-scoped contact and message
  # calls below are allowed to run.
  @spec build_context(non_neg_integer()) :: map() | nil
  defp build_context(organization_id) do
    organization = Partners.organization(organization_id)
    Repo.put_current_user(organization.root_user)
  end

  # Best-effort send: the caller always gets the same neutral response regardless of what
  # happens here (see request_otp_for/3). Failures are logged internally instead.
  #
  # The rescue is load-bearing, not defensive padding. Not every failure down this path arrives
  # as an {:error, _} tuple that `else` can catch — `Messages.create_and_send_otp_template_message/2`
  # hard-matches on fetching the "verify_otp" HSM template (messages.ex:466), so an organization
  # that has not had that template approved *raises* here. Without the rescue that would surface
  # as a 500 and break the neutral-response guarantee this endpoint exists to provide, turning a
  # missing-template misconfiguration into an enumeration oracle.
  @spec send_web_channel_otp(non_neg_integer(), String.t()) :: :ok
  defp send_web_channel_otp(organization_id, phone) do
    build_context(organization_id)

    with {:ok, contact} <- optin_contact(organization_id, phone),
         true <- can_send_message_to?(contact),
         code = OTP.generate_code(:web_channel, phone),
         {:ok, _message} <- Messages.create_and_send_otp_verification_message(contact, code) do
      :ok
    else
      error ->
        # send_appsignal? is false on purpose. A beneficiary who is opted out, blocked or simply
        # not on WhatsApp fails `can_send_message_to?/1`, and that is ordinary traffic for a public
        # login form, not an incident — paging on it would make the noise proportional to usage.
        # The staff path logs the same case at Logger level for the same reason
        # (registration_controller.ex:203-206).
        #
        # Never inspect/1 an error term that may hold a %Tesla.Env{} — it can carry a live
        # Authorization header. SafeLog.safe_inspect/1 strips it first.
        Glific.log_error(
          "Failed to send web channel OTP to #{Glific.mask_phone_number(phone)}: " <>
            SafeLog.safe_inspect(error),
          false
        )

        :ok
    end
  rescue
    exception ->
      # An unexpected raise is a real misconfiguration worth paging on, unlike the routine
      # delivery failures above — so this one does reach AppSignal.
      Glific.log_error(
        "Could not send web channel OTP to #{Glific.mask_phone_number(phone)} " <>
          "for organization #{organization_id}: #{describe_send_failure(exception)}"
      )

      :ok
  end

  # The bare exception is not actionable on call. The overwhelmingly likely cause is the
  # precondition from #5662: the organization has no approved `verify_otp` HSM template, so
  # `Messages.create_and_send_otp_template_message/2` hard-matches on a missing row
  # (messages.ex:466) and every contact outside the 24 hour session window fails. Say that,
  # rather than making whoever reads the alert reverse-engineer a MatchError.
  @spec describe_send_failure(Exception.t()) :: String.t()
  defp describe_send_failure(%MatchError{
         term: {:error, ["Elixir.Glific.Templates.SessionTemplate", "Resource not found"]}
       }),
       do:
         "no approved HSM template with shortcode \"verify_otp\" exists for this organization, " <>
           "so a contact outside the 24 hour session window cannot be sent a code. " <>
           "Approve that template before enabling the web channel for this organization."

  defp describe_send_failure(exception), do: SafeLog.safe_inspect(exception)

  @spec optin_contact(non_neg_integer(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp optin_contact(organization_id, phone) do
    %{
      phone: phone,
      organization_id: organization_id,
      method: "web_channel"
    }
    |> Contacts.contact_opted_in(organization_id, DateTime.utc_now(), method: "web_channel")
  end

  # ORs the HSM and session checks — either is sufficient to attempt delivery.
  @spec can_send_message_to?(Contact.t()) :: boolean()
  defp can_send_message_to?(contact) do
    hsm = Contacts.can_send_message_to?(contact, true)
    session = Contacts.can_send_message_to?(contact, false)
    elem(hsm, 0) == :ok || elem(session, 0) == :ok
  end

  @spec unprocessable_entity_error(Conn.t(), String.t()) :: Conn.t()
  defp unprocessable_entity_error(conn, message) do
    conn
    |> put_status(422)
    |> json(%{error: %{status: 422, message: message}})
  end

  @spec web_channel_disabled_error(Conn.t()) :: Conn.t()
  defp web_channel_disabled_error(conn) do
    conn
    |> put_status(404)
    |> json(%{error: %{status: 404, message: "Web channel is not enabled for this organization"}})
  end

  @spec invalid_otp_error(Conn.t()) :: Conn.t()
  defp invalid_otp_error(conn) do
    conn
    |> put_status(401)
    |> json(%{error: %{status: 401, message: "Invalid OTP"}})
  end
end
