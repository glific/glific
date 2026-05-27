defmodule Glific.Mails.SyncDisabledMail do
  @moduledoc """
  Sends a weekly email to the internal team listing organizations
  whose BigQuery or GCS credentials are currently disabled.
  """

  alias Glific.{
    Communications.Mailer,
    Partners,
    Partners.Saas
  }

  @internal_team_mail "info@glific.org"

  @doc """
  Fetches disabled-credential orgs for both BigQuery and GCS and sends the
  report email only when at least one list is non-empty.
  """
  @spec send_if_any() :: :ok
  def send_if_any do
    bq_orgs = Partners.list_orgs_with_disabled_credential("bigquery")
    gcs_orgs = Partners.list_orgs_with_disabled_credential("google_cloud_storage")

    if bq_orgs != [] or gcs_orgs != [] do
      new_mail(bq_orgs, gcs_orgs)
      |> Mailer.send(%{
        category: "sync_disabled_report",
        organization_id: Saas.organization_id()
      })
    end

    :ok
  end

  @doc """
  Builds a Swoosh email with two HTML tables: one for BigQuery-disabled orgs
  and one for GCS-disabled orgs.
  """
  @spec new_mail(list(map()), list(map())) :: Swoosh.Email.t()
  def new_mail(bq_orgs, gcs_orgs) do
    subject = "Weekly sync-disabled report: BigQuery & GCS"
    html_body = to_html(bq_orgs, gcs_orgs)

    opts = [
      is_html: true,
      team: "",
      send_to: {"Glific Team", @internal_team_mail},
      ignore_cc_support: true
    ]

    Mailer.common_send(nil, subject, html_body, opts)
  end

  @spec to_html(list(map()), list(map())) :: String.t()
  defp to_html(bq_orgs, gcs_orgs) do
    """
    <html>
    <body style="font-family: Arial, sans-serif;">
      <h2>Weekly Sync-Disabled Report</h2>
      <p>The following organizations have their BigQuery or GCS credentials disabled.
         Their syncs will remain paused until the credential is manually re-enabled.</p>

      <h3>BigQuery — Disabled Credentials (#{length(bq_orgs)} org(s))</h3>
      #{table(bq_orgs)}

      <h3>GCS — Disabled Credentials (#{length(gcs_orgs)} org(s))</h3>
      #{table(gcs_orgs)}
    </body>
    </html>
    """
  end

  @spec table(list(map())) :: String.t()
  defp table([]) do
    "<p><em>None</em></p>"
  end

  defp table(orgs) do
    rows =
      Enum.map(orgs, fn %{id: id, name: name, disabled_since: disabled_since} ->
        """
        <tr>
          <td>#{name}</td>
          <td>#{id}</td>
          <td>#{Calendar.strftime(disabled_since, "%Y-%m-%d %H:%M UTC")}</td>
        </tr>
        """
      end)

    """
    <table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse;">
      <thead style="background-color: #f2f2f2;">
        <tr>
          <th>Org Name</th>
          <th>Org ID</th>
          <th>Disabled Since</th>
        </tr>
      </thead>
      <tbody>
        #{Enum.join(rows, "\n")}
      </tbody>
    </table>
    """
  end
end
