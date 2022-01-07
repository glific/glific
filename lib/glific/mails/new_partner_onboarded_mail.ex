defmodule Glific.Mails.NewPartnerOnboardedMail do
  import Swoosh.Email
  alias Glific.Communications.Mailer
  alias Glific.Partners.Saas

  def new_mail(org) do
    new()
    |> from(Mailer.sender())
    |> to({"", Saas.primary_email()})
    |> subject("Congratulations! We onboarded new NGO.")
    |> text_body(
      "Hello Team\nA new organization is onboarded on Tides.\n\n Name: #{org.name}\n Email: #{org.email}"
    )
  end
end
