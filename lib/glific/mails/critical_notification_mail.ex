defmodule Glific.Mails.CriticalNotificationMail do
  import Swoosh.Email
  alias Glific.Communications.Mailer

  def new_mail(org, message) do
    new()
    |> to({org.name, org.email})
    |> from(Mailer.sender())
    |> subject("CRITICAL: Needs your attention.")
    |> text_body("Hello #{org.name}\nThere is one critical error on Glific.
      \n#{message} \n\n Please contact the Glific team in case you don't understand the issue.
      \n\n The Glific team")
  end
end
