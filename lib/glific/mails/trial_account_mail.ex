defmodule Glific.Mails.TrialAccountMail do
  @moduledoc """
  TrialAccountMails will have the content for the trial accounts email notifications.
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization,
    Partners.Saas,
    TrialUsers
  }

  @glific_email {"Glific Team", "connect@glific.org"}

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
      from_email: @glific_email,
      ignore_cc_support: true
    )
  end

  @doc """
  Sends welcome email to trial users
  """
  @spec welcome_to_trial_account(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
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
      from_email: @glific_email,
      ignore_cc_support: true
    )
  end

  @doc """
  Sends trial account allocated email notification to Biz Dev
  """
  @spec trial_account_allocated(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
  def trial_account_allocated(organization, trial_user) do
    subject = "Glific: A new trial account has been allocated"
    body = create_trial_account_allocated_body(organization.shortcode, trial_user)

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: [@glific_email],
      ignore_cc_support: true
    )
  end

  @doc """
  Sends trial account allocation failure email notification to Biz Dev
  """
  @spec trial_account_allocation_failed(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
  def trial_account_allocation_failed(organization, trial_user) do
    subject = "Glific: Trial account allocation failed (no accounts available)"
    body = create_trial_account_allocation_failure_body(trial_user)

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: [@glific_email],
      ignore_cc_support: true
    )
  end

  @doc """
  Sends day 3 follow-up email to trial users
  """
  @spec day_3_followup(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
  def day_3_followup(organization, trial_user) do
    subject = "Have you tried the Glific platform yet?"
    body = create_day_3_followup_body(organization.shortcode, trial_user)

    recipients = [
      {"#{trial_user.username}", trial_user.email}
    ]

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: recipients,
      from_email: @glific_email,
      ignore_cc_support: true
    )
  end

  @doc """
  Sends day 6 follow-up email to trial users with social proof and case studies
  """
  @spec day_6_followup(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
  def day_6_followup(organization, trial_user) do
    subject = "How other NGOs are using Glific (ideas for your trial)"
    body = create_day_6_followup_body(organization.shortcode, trial_user)

    recipients = [
      {"#{trial_user.username}", trial_user.email}
    ]

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: recipients,
      from_email: @glific_email,
      ignore_cc_support: true
    )
  end

  @doc """
  Sends day 12 follow-up email to trial users with conversion and next steps
  """
  @spec day_12_followup(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
  def day_12_followup(organization, trial_user) do
    subject = "Your Glific trial – next steps & how we can support"
    body = create_day_12_followup_body(organization.shortcode, trial_user)

    recipients = [
      {"#{trial_user.username}", trial_user.email}
    ]

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: recipients,
      from_email: @glific_email,
      ignore_cc_support: true
    )
  end

  @doc """
  Sends day 14 follow-up email to trial users on their last day
  """
  @spec day_14_followup(Organization.t(), TrialUsers.t()) :: Swoosh.Email.t()
  def day_14_followup(organization, trial_user) do
    subject = "Your Glific trial ends today – what's next?"
    body = create_day_14_followup_body(organization.shortcode, trial_user)

    recipients = [
      {"#{trial_user.username}", trial_user.email}
    ]

    Mailer.common_send(
      organization,
      subject,
      body,
      send_to: recipients,
      from_email: @glific_email,
      ignore_cc_support: true
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

  @spec create_welcome_mail_body(String.t(), TrialUsers.t()) :: String.t()
  defp create_welcome_mail_body(shortcode, trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>Hi #{trial_user.username},</p>

      <p>Welcome to Glific! 🎉</p>

      <p>Thank you for signing up for a trial. With Glific, you can:</p>

      <ul>
        <li>Run two-way WhatsApp conversations with your communities</li>
        <li>Automate FAQs, reminders, follow-ups, and more</li>
        <li>Track responses and impact in real time</li>
      </ul>

      <p>To help you get started:</p>

      <ol>
        <li>Here's the link to the platform: <a href="https://#{shortcode}.glific.com">https://#{shortcode}.glific.com</a></li>
        <li>Here's a short <a href="https://www.youtube.com/watch?v=OH4rDB6wlx0">video</a> that shows you how to create your first flow on Glific</li>
      </ol>

      <p>If you'd like a quick walkthrough, you can book a 30 min demo with us <a href="https://calendly.com/aishwarya-cs-projecttech4dev/30min?utm_medium=trial%20accounts">here</a>. Or if you have any questions, write to us by replying to this email.</p>

      <p>Looking forward to helping you make the most of your trial.</p>

      <p>Warm regards,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end

  @spec create_trial_account_allocated_body(String.t(), TrialUsers.t()) :: String.t()
  defp create_trial_account_allocated_body(shortcode, trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>A new trial account has been allocated. Details of trial account user:</p>

      <ul>
        <li><strong>Name:</strong> #{trial_user.username}</li>
        <li><strong>Organization:</strong> #{trial_user.organization_name}</li>
        <li><strong>Email:</strong> #{trial_user.email}</li>
        <li><strong>Phone Number:</strong> #{trial_user.phone}</li>
        <li><strong>Login URL:</strong> <a href="https://#{shortcode}.glific.com">https://#{shortcode}.glific.com</a></li>
      </ul>

      <p>Best,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end

  @spec create_trial_account_allocation_failure_body(TrialUsers.t()) :: String.t()
  defp create_trial_account_allocation_failure_body(trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>A trial account could not be allocated because no trial accounts are currently available.</p>

      <p><strong>User details:</strong></p>
      <ul>
        <li><strong>Name:</strong> #{trial_user.username}</li>
        <li><strong>Organization:</strong> #{trial_user.organization_name}</li>
        <li><strong>Email:</strong> #{trial_user.email}</li>
        <li><strong>Phone Number:</strong> #{trial_user.phone}</li>
      </ul>

      <p>Please reach out to the user, as the user has already completed OTP verification.</p>

      <p>Best,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end

  @spec create_day_3_followup_body(String.t(), TrialUsers.t()) :: String.t()
  defp create_day_3_followup_body(_shortcode, trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>Hi #{trial_user.username},</p>

      <p>Checking in to see how your Glific trial is going.</p>

      <p>Most NGOs start with one simple step:<br>
      <strong>Create 1 flow + send a message on the preview (simulator) to test</strong></p>

      <p>You could use Glific to:</p>
      <ul>
        <li>Share program reminders with beneficiaries</li>
        <li>Collect quick surveys from the field</li>
        <li>Send event reminders</li>
      </ul>

      <p>If you're stuck at any point, just reply to this email and tell us where you're blocked — we'll help you sort it out. You can <a href="https://calendly.com/aishwarya-cs-projecttech4dev/30min?utm_medium=trial%20accounts">book a slot to have a chat with us</a>.</p>

      <p>You can also follow this <a href="https://glific.org/quick-start-guide/">quick start guide</a>.</p>

      <p>Best,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end

  @spec create_day_6_followup_body(String.t(), TrialUsers.t()) :: String.t()
  defp create_day_6_followup_body(_shortcode, trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>Hi #{trial_user.username},</p>

      <p>Sharing a few ways NGOs like yours use Glific:</p>

      <p><strong>Antarang Foundation</strong> — Uses a WhatsApp chatbot to scale career guidance for students. (<a href="https://glific.org/antarang-foundation/">See full case study</a>)</p>

      <p><strong>Reap Benefit</strong> — Runs a WhatsApp-bot powered "Solve Ninja" programme for youth civic & climate engagement via nudges, data collection & follow-up. (<a href="https://glific.org/reap-benefit/">See full case study</a>)</p>

      <p><strong>The Apprentice Project (TAP)</strong> — Uses the "TAP Buddy" WhatsApp chatbot to deliver self-learning electives & build 21st-century skills for underserved students. (<a href="https://glific.org/the-apprentice-project/">See TAP Buddy in action</a>)</p>

      <p>Here's a link showing <a href="https://glific.org/case-studies/">how similar NGOs are using Glific</a> — along with examples you can explore.</p>

      <p>Tell us what you're trying to achieve, and we'll recommend the flow, templates, and setup steps that will help you get there faster.</p>

      <p>You can book a 30 min conversation with us here: <a href="https://calendly.com/aishwarya-cs-projecttech4dev/30min?utm_medium=trial%20accounts">Link</a>. Or if you have any questions, write to us by replying to this email.</p>

      <p>Regards,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end

  @spec create_day_12_followup_body(String.t(), TrialUsers.t()) :: String.t()
  defp create_day_12_followup_body(_shortcode, trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>Hi #{trial_user.username},</p>

      <p>Your Glific trial will end in two days, so we wanted to check in on:</p>
      <ul>
        <li>What you've been able to try so far</li>
        <li>Any blockers you faced</li>
        <li>Whether you'd like to continue with a paid plan</li>
      </ul>

      <p>If you'd like to:</p>
      <p><strong>Continue using Glific:</strong> We have one plan to make it easy for organisations to get started. Find about the pricing <a href="https://glific.org/pricing/">here</a>.</p>

      <p><strong>Talk to someone:</strong> Book a short call here so we can review your trial and map the right next steps: <a href="https://calendly.com/aishwarya-cs-projecttech4dev/30min?utm_medium=trial%20accounts">Link</a></p>

      <p>Best,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end

  @spec create_day_14_followup_body(String.t(), TrialUsers.t()) :: String.t()
  defp create_day_14_followup_body(_shortcode, trial_user) do
    """
    <!DOCTYPE html>
    <html>
    <body>
      <p>Hi #{trial_user.username},</p>

      <p>Your Glific trial ends today, so this is a quick check-in to see how your experience has been and what you'd like to do next.</p>

      <p>Here are a few options:</p>

      <p><strong>➡ Continue using Glific</strong><br>
      We have one plan to make it easy for organisations to get started — as low as ₹300 (USD 4) per day. Find the pricing details <a href="https://glific.org/pricing/">here</a>.</p>

      <p><strong>➡ Need support or have questions?</strong><br>
      Book a short call and we'll walk you through setup, flows, and next steps: <a href="https://calendly.com/aishwarya-cs-projecttech4dev/30min?utm_medium=trial%20accounts">Link</a></p>

      <p><strong>➡ Not continuing right now?</strong><br>
      No problem — even a quick note on your experience would really help us improve.</p>

      <p>Thanks again for trying Glific.</p>

      <p>Best,<br>
      Team Glific</p>

      <p><em>Built for nonprofits. Designed for impact.</em></p>
    </body>
    </html>
    """
  end
end
