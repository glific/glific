defmodule Glific.Mails.NewPartnererOnboardedMail do
  import Swoosh.Email
  alias Glific.Communications.Mailer
  alias Glific.Partners.Saas

  def new_mail(org) do
    new()
    |> to({"", Saas.primary_email()})
    |> from(Mailer.sender())
    |> subject("Congratulations! We onboarded new NGO.")
    |> text_body(
      "Hello Team\n We have onboaded new organization on Tides.\n\n  Name: #{org.name}\n Email: #{org.email}"
    )
  end
end
