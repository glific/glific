defmodule Glific.Mails.CriticalNotificationMail do
  @moduledoc """
  CriticalNotificationMail is a mail that is sent to the org admin when a critical error occurs.
  """
  import Swoosh.Email
  alias Glific.Communications.Mailer

  @doc """
  Sends a critical notification mail to the org admin.
  """
  @spec new_mail(map(), String.t()) :: Swoosh.Email.t()
  def new_mail(org, message) do
    new()
    |> to({org.name, org.email})
    |> from(Mailer.sender())
    |> cc(Mailer.glific_support())
    |> subject("CRITICAL: Needs your attention.")
    |> text_body("Hello #{org.name}\nThere is one critical error on Glific.
      \n#{message} \n\n Please contact the Glific team in case you don't understand the issue.
      \n\n The Glific team")
  end
end
