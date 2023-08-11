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

    body = """
      <h2>Monthly Report</h2>
      #{html_body}

      For more insights checkout <a href="https://api.glific.test:4001/stats" target="_blank">Your Dashboard</a>
    """

    Mailer.common_html_send(org, subject, body)
  end
end
