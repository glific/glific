defmodule Glific.Mails.NotificationMail do
  @moduledoc """
  NotificationMail is a mail that is sent to the org admin when an error occurs.
  """
  alias Glific.{Communications.Mailer, Partners.Organization}

  @doc """
  Sends a critical notification mail to the org admin.
  """
  @spec critical_mail(Organization.t(), String.t()) :: Swoosh.Email.t()
  def critical_mail(org, message) do
    team = ""
    subject = "Glific CRITICAL Issue: Needs your immediate attention."

    body = """
    Hello #{org.name}
    Your Glific instance has run into this critical error: #{message}
    Please contact the Glific team in case you don't understand the issue.
    The Glific team
    """

    Mailer.common_send(org, subject, body, team: team)
  end

  @doc """
  Sends a warning notification mail to the org admin.
  """
  @spec warning_mail(Organization.t(), String.t()) :: Swoosh.Email.t()
  def warning_mail(org, message) do
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
