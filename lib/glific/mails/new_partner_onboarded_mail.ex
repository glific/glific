defmodule Glific.Mails.NewPartnerOnboardedMail do
  @moduledoc """
  NewPartnerOnboardedMail will have the content for formatting for the new partner onboarded email.
  """

  import Swoosh.Email
  alias Glific.Communications.Mailer
  alias Glific.Partners.Saas

  @spec new_mail(map()) :: Swoosh.Email.t()
  def new_mail(org) do
    new()
    |> from(Mailer.sender())
    |> to({"", Saas.primary_email()})
    |> cc(Mailer.glific_support())
    |> subject("Congratulations! We onboarded new NGO.")
    |> text_body(
      "Hello Team\nA new organization is onboarded on Tides.\n\n Name: #{org.name}\n Email: #{org.email}"
    )
  end
end
