defmodule Glific.Mails.DashboardMail do
  @moduledoc """
  A montly report sent to organization
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization
  }
  alias GlificWeb.{DashboardView}

  @doc """
  Sends a mail to the organization with snippet of internal dashboard
  """
  @spec new_mail(Organization.t(), map(), [{atom(), any()}]) :: Swoosh.Email.t()
  def new_mail(org, assigns, opts \\ []) do
    subject = "Internal Dashboard: Report"

    template = Keyword.get(opts, :template)

    html_body = DashboardView.render_dashboard(template, assigns)

    # body = """
    # Dear #{org.parent_org} Team,

    # We hope this message finds you well. As part of our commitment to provide you with valuable insights into the performance of your Glific-powered WhatsApp chatbot, we're pleased to share the Weekly Chatbot Performance Report for the period [Date Range].

    # #{html_body}

    # Please feel free to reach out to us if you have any questions, need further assistance, or would like to dive deeper into the data. Our team is here to support you in maximizing the impact of your chatbot and achieving your goals.

    # Best Regards,
    # Team Glific
    # """

    Mailer.common_html_send(org, subject, html_body)
  end
end
