defmodule Glific.Mails.ReportGupshupMail do
  @moduledoc """
  ReportGupshupMail is a mail that is sent to the Gupshup Support team.
  """
  alias Glific.{Communications.Mailer, Partners.Organization}

  @gupshup_support {"Gupshup Dev Support", "devsupport@gupshup.io"}
  @sender {"Glific support", "mohit@coloredcow.in"}

  @doc """
  Sends a mail to the Gupshup support team whenever issue arises related to approval of the template
  """
  @spec raise_to_gupshup(Organization.t(), String.t(), String.t(), [{atom(), any()}]) ::
          Swoosh.Email.t()
  def raise_to_gupshup(org, app_id, app_name, opts \\ []) do
    subject = "Issue Regarding templates approval"

    phone = Keyword.get(opts, :phone, "")
    bsp_id = Keyword.get(opts, :bsp_id, "")
    cc = Keyword.get(opts, :cc, [])

    body = """
    Hi Gupshup Team,

    One of the templates we applied has been rejected.  Please find below details

    1. APP ID: #{app_id}
    2. Registered phone number: #{phone}
    3. App name: #{app_name}
    4. Rejected Template ID: #{bsp_id}
    """

    options = [
      send_to: @gupshup_support,
      in_cc: cc,
      from_email: @sender
    ]

    Mailer.common_send(org, subject, body, options)
  end
end
