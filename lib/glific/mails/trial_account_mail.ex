defmodule Glific.Mails.TrialAccountMail do
  @moduledoc """
  TrialAccountMails will have the content for the trial accounts email notifications.
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization
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
      {"#{username}", email}
    ]

    Mailer.common_send(
      org,
      subject,
      body,
      send_to: recipients,
      from_email: {"Glific Team", "connect@glific.org"},
      ignore_cc_support: true
    )
  end

  def welcome_to_trial_account(organization, trial_user) do
    subject = "Welcome to Glific — let’s get started"
    body = create_welcome_mail_body(organization.shortcode, trial_user)

    recipients = [
      {"User", trial_user.email},
      {"Glific", Saas.primary_email()}
    ]

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: recipients,
      from_email: {"Glific Team", "connect@glific.org"},
      ignore_cc_support: true,
      in_cc: []
    )
  end

  def trial_account_allocated(organization, trial_user) do
    subject = "Glific: A new trial account has been allocated"
    body = create_trial_account_allocated_body(organization.shortcode, trial_user)

    recipients = [
      {"Glific Team", "connect@glific.org"}
    ]

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: recipients,
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

  def create_welcome_mail_body(shortcode, trial_user) do
    """
    Hi #{trial_user.username},<br><br>

    Welcome to Glific! 🎉<br><br>

    Thank you for signing up for a trial. With Glific, you can:<br><br>

    &#8226 Run two-way WhatsApp conversations with your communities<br>
    &#8226 Automate FAQs, reminders, follow-ups, and more<br>
    &#8226 Track responses and impact in real time<br><br>

    To help you get started:<br><br>

    1. Here’s the link to the platform: <a href="https://#{shortcode}.glific.com">https://#{shortcode}.glific.com</a> <br>
    2. Here’s a short <a href="https://www.youtube.com/watch?v=OH4rDB6wlx0">video</a> that shows you how to create your first flow on Glific<br><br>

    If you’d like a quick walkthrough, you can book a 30 min demo with us here:  <a href="https://calendly.com/aishwarya-cs-projecttech4dev/30min?utm_medium=trial%20accounts">Link</a>. Or if you have any questions, write to us by replying to this email.<br><br>

    Looking forward to helping you make the most of your trial.<br><br>

    Warm regards,<br>
    Team Glific<br><br>

    <i>Built for nonprofits. Designed for impact.</i>
    """
  end

  def create_trial_account_allocated_body(shortcode, trial_user) do
    """
    A new trial account has been allocated. Details of trial account user:<br><br>

    Name: #{trial_user.username}<br>
    Organization: #{trial_user.organization_name}<br>
    Email: #{trial_user.email}<br>
    Phone Number: #{trial_user.phone}<br>
    Login URL: <a href="https://#{shortcode}.glific.com">https://#{shortcode}.glific.com</a><br><br>

    Best,<br>
    Team Glific<br><br>

    <i>Built for nonprofits. Designed for impact.</i>
    """
  end
end
