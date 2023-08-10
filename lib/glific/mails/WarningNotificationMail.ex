defmodule Glific.Mails.WarningNotificationMailNotificationMail do
  @moduledoc """
  WarningNotificationMail is a mail that is sent to the org admin when a warning occurs.
  """
  alias Glific.{Communications.Mailer, Partners.Organization}

  @doc """
  Sends a warning notification mail to the org admin.
  """
  @spec new_mail(Organization.t(), String.t()) :: Swoosh.Email.t()
  def new_mail(org, message) do
    team = ""
    subject = "Glific warning: Needs your attention."

    body = """
    Hello #{org.name}

    Your Glific instance has run into this warning : #{message}

    Please contact the Glific team in case you don't understand the issue.

    The Glific team
    """

    Mailer.common_send(org, subject, body, team: team)
  end
end
