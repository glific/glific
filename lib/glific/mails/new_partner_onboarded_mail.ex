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
  @spec support_mail(Organization.t(), map()) :: Swoosh.Email.t()
  def support_mail(org, login_details) do
    team = "support"

    subject = """
    Glific: New Partner Onboarded - #{org.name}
    """

    body = """
    Hello Glific Support Team,

    A new partner organization has been successfully onboarded.

    Organization Details:
    ---------------------
    Name: #{org.name}
    Email: #{org.email}

    Login Details:
    --------------
    Phone Number: #{login_details[:phnum]}
    Password: #{login_details[:password]}

    """

    opts = [
      team: team,
      send_to: {"Glific Support", Saas.primary_email()}
    ]

    Mailer.common_send(org, subject, body, opts)
  end

  @doc false
  @spec new_mail(Organization.t()) :: Swoosh.Email.t()
  def new_mail(org) do
    team = ""

    subject = """
    Glific: Congratulations! We onboarded a new NGO.
    """

    body = """
    Hello Glific Team

    A new organization is onboarded on Glific.

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
  def user_query_mail(query, saas_org) do
    team = "operations"

    subject = """
    Glific Support: User query regarding onboarding.
    """

    body = """
    #{query["message"]}


    Name: #{query["name"]},
    Organization Name: #{query["org_name"]},
    Email: #{query["email"]}
    """

    opts = [
      team: team
    ]

    Mailer.common_send(saas_org, subject, body, opts)
  end

  @doc false
  @spec confirmation_mail(map()) :: Swoosh.Email.t()
  def confirmation_mail(params) do
    subject = "Thank you for joining Glific!"

    body =
      """
      Hello #{params["signing_authority"]["name"]},<br><br>

      Thank you for choosing Glific to run your chatbot program. This email serves as confirmation that we have received the registration form submitted by #{params["submitter"]["name"]} for the creation of a Glific platform. <br><br>

      Please find <a href="https://glific.org/glific-terms-and-conditions/">Terms & Conditions</a> for the use of the Glific platform attached here with for your review if needed. <br><br>

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
