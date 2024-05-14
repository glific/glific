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

  @doc false
  @spec user_query_mail(map(), Organization.t()) :: Swoosh.Email.t()
  def user_query_mail(query, org) do
    team = "operations"

    subject = """
    Glific Support: User query regarding onboarding.
    """

    body = """
    #{query["message"]}


    Name: #{query["name"]}
    Email: #{query["email"]}
    """

    opts = [
      team: team
    ]

    Mailer.common_send(org, subject, body, opts)
  end

  @doc false
  @spec confirmation_mail(map()) :: Swoosh.Email.t()
  def confirmation_mail(params) do
    subject = "Confirmation of accepting T&C"

    body =
      """
      Hello #{params["signing_authority"]["name"]},<br><br>

      Thank you for choosing Glific to run your chatbot program. This email serves as confirmation that we have received the registration form submitted by #{params["submitter"]["name"]} for the creation of a Glific platform. <br><br>

      Please find <a href="https://glific.org/">Terms & Conditions</a> for the use of the Glific platform attached here with for your review if needed. <br><br>

      We look forward to an amazing collaboration and scaling your impact together! <br><br>

      Regards,<br>
      Team Glific
      """

    opts = [
      send_to: {"", params["signing_authority"]["email"]},
      is_html: true
    ]

    Mailer.common_send(nil, subject, body, opts)
  end
end
