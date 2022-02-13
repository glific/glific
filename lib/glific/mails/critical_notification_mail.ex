defmodule Glific.Mails.CriticalNotificationMail do
  @moduledoc """
  CriticalNotificationMail is a mail that is sent to the org admin when a critical error occurs.
  """
  alias Glific.Communications.Mailer

  @doc """
  Sends a critical notification mail to the org admin.
  """
  @spec new_mail(map(), String.t()) :: Swoosh.Email.t()
  def new_mail(org, message) do
    subject = "Glific CRITICAL Issue: Needs your immediate attention."

    body = """
    Hello #{org.name}

    Your Glific instance has run into this critical error: #{message}

    Please contact the Glific team in case you don't understand the issue.

    The Glific team
    """

    Mailer.common_send(org, subject, body)
  end
end
