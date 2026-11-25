defmodule Glific.WebChannel.Metrics do
  @moduledoc """
  The web channel's product counters, kept in each organization's daily tracker through
  `Glific.Metrics`.

  The sign-in funnel reconciles: every `"Web OTP Requested"` ends as exactly one of
  `"Web OTP Sent"` or a `"Web OTP Refused: …"` reason.

  Nothing is counted while the web channel is off for the organization, and no counter name
  carries anything that identifies a contact.
  """

  require Logger

  alias Glific.Metrics
  alias GlificWeb.WebChannel.Flag

  @events %{
    otp_requested: "Web OTP Requested",
    otp_sent: "Web OTP Sent",
    otp_refused_invalid_phone: "Web OTP Refused: Invalid Phone",
    otp_refused_rate_limited: "Web OTP Refused: Rate Limited",
    otp_refused_undeliverable: "Web OTP Refused: Undeliverable",
    otp_verified: "Web OTP Verified",
    otp_verify_failed: "Web OTP Verification Failed",
    sign_in_failed: "Web Sign In Failed",
    media_upload_issued: "Web Media Upload Issued",
    media_upload_completed: "Web Media Upload Completed",
    message_sent_staff: "Web Message Sent: Staff",
    message_sent_flow: "Web Message Sent: Flow",
    optin_recorded: "Web Opt-in Recorded"
  }

  @type event() ::
          :otp_requested
          | :otp_sent
          | :otp_refused_invalid_phone
          | :otp_refused_rate_limited
          | :otp_refused_undeliverable
          | :otp_verified
          | :otp_verify_failed
          | :sign_in_failed
          | :media_upload_issued
          | :media_upload_completed
          | :message_sent_staff
          | :message_sent_flow
          | :optin_recorded

  @doc """
  Count one occurrence of a web channel event for an organization.
  """
  @spec count(event(), non_neg_integer()) :: :ok
  def count(event, organization_id), do: bump(Map.fetch!(@events, event), organization_id)

  @doc """
  Count an inbound web message by its type, e.g. `"Web Message Received: image"`.
  """
  @spec count_received(atom(), non_neg_integer()) :: :ok
  def count_received(type, organization_id),
    do: bump("Web Message Received: #{type}", organization_id)

  # A counter must never fail what it measures, so a failure here is logged and swallowed.
  @spec bump(String.t(), non_neg_integer()) :: :ok
  defp bump(name, organization_id) do
    if Flag.web_channel_enabled?(organization_id), do: Metrics.increment(name, organization_id)
    :ok
  rescue
    error ->
      Logger.error("Web channel metric #{name} not counted: #{Exception.message(error)}")
      :ok
  end
end
