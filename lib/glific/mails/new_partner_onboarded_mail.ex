defmodule Glific.Mails.NewPartnerOnboardedMail do
  @moduledoc """
  NewPartnerOnboardedMail will have the content for formatting for the new partner onboarded email.
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization,
    Partners.Saas
  }

  # TODO: Use real mails, and also think about getting from DB
  # @reachout_send_to {"operations", "operations@projecttech4dev.org"}
  # @reachout_cc {"", "operations@projecttech4dev.org"}

  @reachout_send_to {"operations", "operations@projecttech4dev.org"}
  @reachout_cc [{"", "operations@projecttech4dev.org"}]

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

  @doc false
  @spec user_query_mail(map()) :: Swoosh.Email.t()
  def user_query_mail(query) do
    subject = """
    Glific Support: User query regarding onboarding.
    """

    body = """
    #{query["message"]}


    Name: #{query["name"]}
    Email: #{query["email"]}
    """

    opts = [
      send_to: @reachout_send_to,
      in_cc: @reachout_cc
    ]

    Mailer.common_send(nil, subject, body, opts)
  end

  # def confirmation_mail(result) do
  #   subject = "Confirmation of accepting T&C"

  #   body = """
  #   We are pleased to confirm that we have received your information submission
  #   regarding our terms and conditions. We have successfullt processed your submission
  #   and acceptance of the T&C is duly noted. Here's all the summary of the information
  #   you have provided:\n\n

  #   Organization details
  #
  #   """
  # end
end
