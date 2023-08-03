defmodule Glific.Mails.ReportGupshupMail do
  @moduledoc """
  ReportGupshupMail is a mail that is sent to the Gupshup Support team.
  """
  alias Glific.{Communications.Mailer, Partners.Organization}

  @gupshup_support {"Gupshup Dev Support", "devsupport@gupshup.io"}

  @doc """
  Sends a mail to the Gupshup support team whenever issue arises related to approval of the template
  """
  @spec templates_approval_mail(Organization.t(), String.t(), String.t(), String.t(), String.t(), [String.t()]) :: Swoosh.Email.t()
  def templates_approval_mail(org, app_id, app_name, phone, bsp_id, cc) do
    subject = "Issue Regarding templates approval"

    body = """
    Hi Gupshup Team,

    One of the templates we applied has been rejected.  Please find below details

    1. APP ID: #{app_id}
    2. Registered phone number: #{phone}
    3. App name: #{app_name}
    4. Rejected Template ID: #{bsp_id}
    """

    Mailer.common_send(org, subject, body, @gupshup_support, cc)
  end
end
