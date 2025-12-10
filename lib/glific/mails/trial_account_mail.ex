defmodule Glific.Mails.TrialAccountMail do
  @moduledoc """
  TrialAccountMails will have the content for formatting for the trial accounts email.
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization,
    Partners.Saas
  }

  @doc """
  Creates OTP verification email
  """
  @spec otp_verification_mail(Organization.t(), String.t(), String.t(), String.t()) ::
          Swoosh.Email.t()
  def otp_verification_mail(org, email, otp_code, username) do
    subject = "Glific: Trial Account OTP"
    body = create_otp_mail_body(otp_code, username)

    recipients = [
      {"User", email},
      {"Glific", Saas.primary_email()}
    ]

    Mailer.common_send(
      org,
      subject,
      body,
      send_to: recipients,
      from_email: {"Glific Team", "connect@glific.org"},
      ignore_cc_support: true,
      in_cc: []
    )
  end

  @spec create_otp_mail_body(String.t(), String.t()) :: String.t()
  defp create_otp_mail_body(otp_code, username) do
    """
    Hi #{username},

    Thank you for registering for a Glific trial account. You’re just one step away from activating your account!

    Your One-Time Password (OTP) for email verification is:

    🔐 **OTP**: #{otp_code}

    Please enter this OTP in the registration form to continue with your trial setup. The OTP is valid for the next 5 minutes.

    If you did not request this, please ignore this email.

    Best,
    Team Glific
    Built for nonprofits. Designed for impact.

    """
  end
end
