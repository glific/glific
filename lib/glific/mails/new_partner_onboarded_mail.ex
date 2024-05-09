defmodule Glific.Mails.NewPartnerOnboardedMail do
  @moduledoc """
  NewPartnerOnboardedMail will have the content for formatting for the new partner onboarded email.
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization,
    Partners.Saas
  }

  @reachout_send_to {"operations", "operations@projecttech4dev.org"}

  @test_mail_send_to {"", "anandu@projecttech4dev.org"}

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
      # send_to: {"", Saas.primary_email()}
      send_to: @test_mail_send_to
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
      send_to: @test_mail_send_to
    ]

    Mailer.common_send(nil, subject, body, opts)
  end

  def confirmation_mail(result) do
    subject = "Confirmation of accepting T&C"

    body =
      """
      Hello #{result["signing_authority"]["name"]},<br><br>

      Thank you for choosing Glific to run your chatbot program. This email serves as confirmation that we have received the registration form submitted by #{result["submitter"]["name"]} for the creation of a Glific platform. <br><br>

      Please find <a href="https://glific.org/">Terms & Conditions</a> for the use of the Glific platform attached here with for your review if needed. <br><br>

      We look forward to an amazing collaboration and scaling your impact together!
      """

    opts = [
      send_to: {"", result["signing_authority"]["email"]},
      is_html: true
    ]

    Mailer.common_send(nil, subject, body, opts)
  end
end
