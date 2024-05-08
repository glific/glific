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

  def confirmation_mail(result) do
    subject = "Confirmation of accepting T&C"

    body =
      """
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Confirmation of accepting T&C</title>
      <style>
      body {
      font-family: Arial, sans-serif;
      background-color: #EDF6F1;
      margin: 0;
      padding: 0;
      }
      .heading {
      text-align: center;
      color: green;
      }
      .content {
      text-align: center;
      padding: 20px;
      }
      .details-section {
      background-color: white;
      border-radius: 10px;
      padding: 15px;
      margin-bottom: 20px;
      }
      .section-heading {
      font-weight: bold;
      }
      </style>
      </head>
      <body>

      <h1 class="heading">Confirmation of accepting T&C</h1>

      <div class="content">
      <p>We are pleased to confirm that we have received your information submission regarding our terms and conditions. We have successfully processed your submission and acceptance of the T&C is duly noted. Here's a summary of the information you have provided:</p>

      <div class="details-section">
      <h2 class="section-heading">Organization details</h2>
      <p>Org name: #{result["org_details"]["name"]}<br>
      Current address: #{result["org_details"]["current_address"]}<br>
      Registered address: #{result["org_details"]["registered_address"]}<br>
      GSTIN number: #{result["org_details"]["gstin"] || ""}
      </p>

      <h2 class="section-heading">Glific Platform details</h2>
      <p>Chatbot number: #{result["platform_details"]["phone"]}<br>
      App name: #{result["platform_details"]["app_name"]}<br>
      Gupshup API key: #{result["platform_details"]["api_key"]}<br>
      URL shortcode: #{result["platform_details"]["shortcode"]}<br>

      <h2 class="section-heading">Billing details</h2>
      <p>Preferred billing frequency: #{result["billing_frequency"]}<br>
      Finance POC name: #{result["finance_poc"]["name"]}<br>
      Finance POC designation: #{result["finance_poc"]["designation"]}<br>
      Finance POC phone number: #{result["finance_poc"]["phone"]}<br>
      Finance POC email: #{result["finance_poc"]["email"]}<br>

      <h2 class="section-heading">Submitter details</h2>
      <p>Name: #{result["submitter"]["name"]}<br>
      Email: #{result["submitter"]["email"]}<br>

      <h2 class="section-heading">Signing authority details</h2>
      <p>Name: #{result["signing_authority"]["name"]}<br>
      name: #{result["signing_authority"]["name"]}<br>
      designation: #{result["signing_authority"]["designation"]}<br>
      email: #{result["signing_authority"]["email"]}<br>

      </div>
      </div>

      </body>
      </html>
      """

    opts = [
      send_to: {"", result["signing_authority"]["email"]},
      is_html: true
    ]

    Mailer.common_send(nil, subject, body, opts)
  end
end
