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
  @spec otp_verification_mail(Organization.t(), String.t(), String.t()) :: Swoosh.Email.t()
  def otp_verification_mail(org, email, otp_code) do
    subject = "Glific: Trial Account OTP"
    body = create_otp_mail_body(otp_code)

    recipients = [
      {"User", email},
      {"Glific", Saas.primary_email()}
    ]

    Mailer.common_send(
      org,
      subject,
      body,
      send_to: recipients
    )
  end

  @spec create_otp_mail_body(String.t()) :: String.t()
  defp create_otp_mail_body(otp_code) do
    """
    Hi there,

    Thank you for signing up to explore Glific Trial Accounts.

    Your One-Time Password (OTP) for email verification is:

    🔐 OTP: #{otp_code}

    Please paste this OTP in the registration form to continue with your trial setup.

    This OTP is valid for the next 5 minutes.

    If you did not request this, please ignore this email.

    Best regards,
    Glific Team
    """
  end
end
