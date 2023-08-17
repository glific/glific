defmodule Glific.Mails.DashboardMail do
  @moduledoc """
  A monthly report sent to organization
  """
  alias Glific.{
    Communications.Mailer,
    Partners.Organization
  }

  alias GlificWeb.DashboardView

  @doc """
  Sends a mail to the organization with snippet of internal dashboard
  """
  @spec new_mail(Organization.t(), map(), [{atom(), any()}]) :: Swoosh.Email.t()
  def new_mail(org, assigns, opts \\ []) do
    subject = "Internal Dashboard: Report"

    template = Keyword.get(opts, :template)

    html_body = DashboardView.render_dashboard(template, assigns)

    Mailer.common_send(org, subject, html_body, is_html: true)
  end
end
