defmodule Glific.Mails.NewPartnerOnboardedMail do
  @moduledoc """
  NewPartnerOnboardedMail will have the content for formatting for the new partner onboarded email.
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization,
    Partners.Saas
  }

  @doc false
  @spec new_mail(Organization.t()) :: Swoosh.Email.t()
  def new_mail(org) do
    team = ""

    subject = """
    Glific: Congratulations! We onboarded a new NGO.
    """

    body = """
    Hello Glific Team

    A new organization is onboarded on Tides.

    Name: #{org.name}
    Email: #{org.email}
    """

    opts = [
      team: team,
      send_to: {"", Saas.primary_email()}
    ]

    Mailer.common_send(org, subject, body, opts)
  end
end
