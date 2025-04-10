defmodule Glific.Mails.MediaSyncMail do
  @moduledoc """
  Formatting the media sync data and create the mailer
  """
  alias Glific.{
    Communications.Mailer
  }

  @internal_dev_mail "glific-devs@projecttech4dev.org"
  @doc """
  Creates a swoosh mail from the media-sync data
  """
  @spec new_mail(list(map())) :: Swoosh.Email.t()
  def new_mail(media_sync_data) do
    subject = "GCS media sync weekly report"
    team = ""
    html_body = to_html(media_sync_data)
    opts = [is_html: true, team: team, send_to: {"", @internal_dev_mail}, ignore_support: true]

    # Since we are passing send_to explicitly, we don't need an org
    Mailer.common_send(nil, subject, html_body, opts)
  end

  @spec to_html(list(map())) :: String.t()
  defp to_html(media_sync_data) do
    rows =
      for %{name: name, organization_id: org_id, all_files: all, unsynced_files: unsynced} <-
            media_sync_data do
        """
        <tr>
          <td>#{name}</td>
          <td>#{org_id}</td>
          <td>#{all}</td>
          <td>#{unsynced}</td>
        </tr>
        """
      end

    """
    <html>
    <body>
      <h2>Weekly Media Sync Report</h2>
      <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">
        <thead>
          <tr>
            <th>Name</th>
            <th>Organization ID</th>
            <th>All Files</th>
            <th>Unsynced Files</th>
          </tr>
        </thead>
        <tbody>
          #{Enum.join(rows, "\n")}
        </tbody>
      </table>
    </body>
    </html>
    """
  end
end
