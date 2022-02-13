defmodule Glific.Mails.NewPartnerOnboardedMail do
  @moduledoc """
  NewPartnerOnboardedMail will have the content for formatting for the new partner onboarded email.
  """
  alias Glific.Communications.Mailer
  alias Glific.Partners.Saas

  @spec new_mail(map()) :: Swoosh.Email.t()
  def new_mail(org) do
    subject = """
    Glific: Congratulations! We onboarded a new NGO.
    """

    body = """
    Hello Glific Team

    A new organization is onboarded on Tides.

    Name: #{org.name}
    Email: #{org.email}
    """

    Mailer.common_send(org, subject, body, {"", Saas.primary_email()})
  end
end
