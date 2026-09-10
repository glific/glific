defmodule GlificWeb.API.V1.WebChannelAuthController do
  @moduledoc """
  Public, unauthenticated OTP auth for the browser web channel widget.

  Authenticates a `Glific.Contacts.Contact`, never a `Glific.Users.User` — deliberately separate
  from the Pow staff flow in `GlificWeb.API.V1.RegistrationController`. The code travels over
  WhatsApp because SMS is not enabled yet (#5659).

  Signing in records no consent. A contact row is created if the number is new, because an HSM has
  to be addressed to one; nothing else about the contact is touched. Consent, and the exemption
  that makes the OTP deliverable to a contact who has never opted in, are #5713's.
  """

  use GlificWeb, :controller

  require Logger

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Messages,
    OTP,
    Partners,
    Repo,
    SafeLog
  }

  alias GlificWeb.WebChannel.{DisplayName, Flag, Token}
  alias Plug.Conn

  # Identical whether or not `phone` is a known contact and whether or not delivery succeeded, so
  # the endpoint cannot be used to enumerate an organization's contacts.
  @request_otp_message "If this number is registered on WhatsApp, you will receive a one-time code"

  # Compile-time, not a config read: a runtime flag can be flipped by an env var or an IEx console
  # on production, and what this prints is a live credential.
  @log_otp Mix.env() == :dev

  # The IP limit is usually a shared network, where "wait 30 seconds" would be wrong advice.
  @phone_throttled_message "An OTP was just sent. Please try again in 30 seconds."
  @ip_throttled_message "Too many sign-in attempts from your network. Please wait a few minutes and try again."

  @doc """
  Requests that an OTP be sent over WhatsApp to `phone`, so a beneficiary can sign in to the
  web channel widget. Always responds 200, whether or not `phone` belongs to a known contact
  and whether or not delivery actually succeeds.
  """
  @spec request_otp(Conn.t(), map()) :: Conn.t()
  def request_otp(conn, %{"phone" => phone}) when is_binary(phone) and phone != "" do
    organization_id = conn.assigns[:organization_id]

    if Flag.web_channel_enabled?(organization_id) do
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
    case check_rate_limit(conn, normalized) do
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

    if Flag.web_channel_enabled?(organization_id) do
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

      # Distinguishing these would tell an attacker whether a code was ever issued for a number.
      {:error, _reason} ->
        invalid_otp_error(conn)
    end
  end

  # The code is already spent by the time we get here, so a hard match on a changeset failure
  # would 500 and strand the caller behind the throttle with no code. Two concurrent verifies for
  # an unknown phone can genuinely race on the (phone, organization_id) unique index.
  @spec resolve_contact_and_sign_in(Conn.t(), non_neg_integer(), String.t()) :: Conn.t()
  defp resolve_contact_and_sign_in(conn, organization_id, normalized) do
    case ensure_contact(organization_id, normalized) do
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

  @doc """
  Exchange a still-valid token for a fresh one, so a one hour TTL does not end a conversation the
  beneficiary is still having.

  Requires the current token to be valid: an expired one is refused rather than resurrected,
  which is what keeps expiry meaningful. Renewal is also bounded in total — see
  `GlificWeb.WebChannel.Token` — so refreshing indefinitely does not grant an indefinite session.
  """
  @spec renew_token(Conn.t(), map()) :: Conn.t()
  def renew_token(conn, %{"token" => token}) when is_binary(token) and token != "" do
    organization_id = conn.assigns[:organization_id]

    if Flag.web_channel_enabled?(organization_id) do
      renew_token_for(conn, organization_id, token)
    else
      web_channel_disabled_error(conn)
    end
  end

  def renew_token(conn, _params),
    do: unprocessable_entity_error(conn, "Token is required")

  @spec renew_token_for(Conn.t(), non_neg_integer(), String.t()) :: Conn.t()
  defp renew_token_for(conn, organization_id, token) do
    case Token.renew_contact_token(token) do
      {:ok, renewed, payload} ->
        build_context(organization_id)
        respond_with_session(conn, renewed, payload, organization_id)

      # One answer for every cause, so a caller cannot probe which.
      {:error, _reason} ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid or expired session"}})
    end
  end

  # The signing key is installation-wide until #5711, so this comparison is the only thing
  # stopping another organization's token being renewed here.
  @spec respond_with_session(Conn.t(), String.t(), map(), non_neg_integer()) :: Conn.t()
  defp respond_with_session(conn, renewed, %{org_id: org_id} = payload, organization_id)
       when org_id == organization_id do
    case Repo.fetch_by(Contact, %{id: payload.contact_id, organization_id: organization_id}) do
      {:ok, contact} ->
        json(conn, %{
          data: %{
            token: renewed,
            contact_id: contact.id,
            name: DisplayName.resolve(contact),
            phone: contact.phone
          }
        })

      # Verified, but the contact is gone — nothing to renew into.
      {:error, _} ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid or expired session"}})
    end
  end

  defp respond_with_session(conn, _renewed, _payload, _organization_id) do
    Glific.log_error("Web channel token renewal attempted across organizations")

    conn
    |> put_status(401)
    |> json(%{error: %{status: 401, message: "Invalid or expired session"}})
  end

  # Two buckets, because neither dimension is sufficient alone and they fail in opposite
  # directions. Keying only on IP is wrong for this audience: beneficiaries reach the internet
  # through carrier-grade NAT, so a whole district can share one address and a 1-per-30s budget
  # becomes a login outage rather than a throttle. Keying only on the phone leaves an attacker
  # free to walk thousands of numbers from one host, each once per window, spending the
  # organization's HSM budget and spamming strangers. So the phone is throttled tightly and the
  # IP loosely — loose enough for a shared NAT, tight enough that enumeration is not free.
  #
  # Both are keyed separately from the staff `send_otp:` limiter, so the web channel never shares
  # a budget with staff registration.
  @spec check_rate_limit(Conn.t(), String.t()) :: :ok | {:error, String.t()}
  defp check_rate_limit(conn, phone) do
    with :ok <-
           check_bucket(
             :web_channel_otp_rate_limit,
             "web_channel_send_otp:#{phone}",
             @phone_throttled_message
           ) do
      check_bucket(
        :web_channel_otp_ip_rate_limit,
        "web_channel_send_otp_ip:#{GlificWeb.Tenants.remote_ip(conn)}",
        @ip_throttled_message
      )
    end
  end

  @spec check_bucket(atom(), String.t(), String.t()) :: :ok | {:error, String.t()}
  defp check_bucket(config_key, key, message) do
    config = Application.get_env(:glific, config_key, [])
    scale_ms = Keyword.get(config, :scale_ms, 30_000)
    count = Keyword.get(config, :count, 1)

    case ExRated.check_rate(key, scale_ms, count) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, message}
    end
  end

  # The permission-checked contact and message calls below raise without a current user.
  @spec build_context(non_neg_integer()) :: map() | nil
  defp build_context(organization_id) do
    organization = Partners.organization(organization_id)
    Repo.put_current_user(organization.root_user)
  end

  # The rescue is load-bearing. `Messages.create_and_send_otp_template_message/2` hard-matches on
  # the "verify_otp" HSM template, so an organization without it *raises* rather than returning
  # {:error, _} — a 500 here would turn a missing-template misconfiguration into an enumeration
  # oracle.
  @spec send_web_channel_otp(non_neg_integer(), String.t()) :: :ok
  defp send_web_channel_otp(organization_id, phone) do
    build_context(organization_id)

    with {:ok, contact} <- ensure_contact(organization_id, phone),
         true <- can_send_message_to?(contact),
         code = mint_code(phone),
         {:ok, _message} <- Messages.create_and_send_otp_verification_message(contact, code) do
      :ok
    else
      error ->
        # send_appsignal? false: a contact who is opted out or simply not on WhatsApp is ordinary
        # traffic for a public login form, so paging would scale the noise with usage. safe_inspect
        # because the error term may hold a %Tesla.Env{} carrying a live Authorization header.
        Glific.log_error(
          "Failed to send web channel OTP to #{Glific.mask_phone_number(phone)}: " <>
            SafeLog.safe_inspect(error),
          false
        )

        :ok
    end
  rescue
    exception ->
      # Unlike the routine failures above, a raise is a real misconfiguration worth paging on.
      Glific.log_error(
        "Could not send web channel OTP to #{Glific.mask_phone_number(phone)} " <>
          "for organization #{organization_id}: #{describe_send_failure(exception)}"
      )

      :ok
  end

  # Local development has no BSP, so the HSM never arrives and there is no way to read the code.
  # It is minted here regardless of whether the send succeeds, so logging it is enough — no bypass
  # in `verify_code/3`, which means dev exercises the same verification path as production.
  @spec mint_code(String.t()) :: String.t()
  defp mint_code(phone) do
    code = OTP.generate_code(:web_channel, phone)
    if @log_otp, do: Logger.info("Web channel OTP for #{phone}: #{code}")
    code
  end

  # So whoever reads the alert does not have to reverse-engineer a MatchError into #5662's
  # missing-template precondition.
  @spec describe_send_failure(Exception.t()) :: String.t()
  defp describe_send_failure(%MatchError{
         term: {:error, ["Elixir.Glific.Templates.SessionTemplate", "Resource not found"]}
       }),
       do:
         "no approved HSM template with shortcode \"verify_otp\" exists for this organization, " <>
           "so a contact outside the 24 hour session window cannot be sent a code. " <>
           "Approve that template before enabling the web channel for this organization."

  defp describe_send_failure(exception), do: SafeLog.safe_inspect(exception)

  # Writes no `optin_*`: typing a number into a public login box is not consent to anything.
  @spec ensure_contact(non_neg_integer(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp ensure_contact(organization_id, phone),
    do: Contacts.maybe_create_contact(%{phone: phone, organization_id: organization_id})

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
