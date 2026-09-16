defmodule Glific.Mails.SyncDisabledMailTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Mails.MailLog,
    Mails.SyncDisabledMail,
    Partners,
    Partners.Credential,
    Partners.Provider,
    Partners.Saas,
    Repo
  }

  describe "new_mail/2" do
    test "builds a Swoosh email with BQ and GCS sections" do
      bq_orgs = [%{id: 1, name: "Org A", disabled_since: ~U[2026-05-01 10:00:00Z]}]
      gcs_orgs = [%{id: 2, name: "Org B", disabled_since: ~U[2026-05-10 08:30:00Z]}]

      email = SyncDisabledMail.new_mail(bq_orgs, gcs_orgs)

      assert email.subject =~ "sync-disabled"
      assert email.html_body =~ "Org A"
      assert email.html_body =~ "Org B"
      assert email.html_body =~ "BigQuery"
      assert email.html_body =~ "GCS"
    end

    test "renders 'None' placeholder for empty tables" do
      email = SyncDisabledMail.new_mail([], [])

      assert String.split(email.html_body, "<em>None</em>") |> length() == 3
    end
  end

  describe "send_if_any/0" do
    test "sends email and logs it when BigQuery orgs are disabled",
         %{organization_id: organization_id} do
      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "bigquery"})

      # Bypass Partners.create_credential: it now validates that bigquery credentials
      # contain a valid service_account JSON, which is irrelevant to this test.
      {:ok, _} =
        %Credential{}
        |> Credential.changeset(%{
          secrets: %{},
          provider_id: provider.id,
          organization_id: organization_id,
          is_active: false
        })
        |> Repo.insert()

      SyncDisabledMail.send_if_any()

      saas_org_id = Saas.organization_id()

      assert MailLog.count_mail_logs(%{
               filter: %{organization_id: saas_org_id, category: "sync_disabled_report"}
             }) == 1
    end

    test "sends email and logs it when GCS orgs are disabled",
         %{organization_id: organization_id} do
      {:ok, _} =
        Partners.create_credential(%{
          shortcode: "google_cloud_storage",
          secrets: %{},
          organization_id: organization_id,
          is_active: false
        })

      SyncDisabledMail.send_if_any()

      saas_org_id = Saas.organization_id()

      assert MailLog.count_mail_logs(%{
               filter: %{organization_id: saas_org_id, category: "sync_disabled_report"}
             }) == 1
    end

    test "does not send email when no credentials are disabled" do
      saas_org_id = Saas.organization_id()

      SyncDisabledMail.send_if_any()

      assert MailLog.count_mail_logs(%{
               filter: %{organization_id: saas_org_id, category: "sync_disabled_report"}
             }) == 0
    end
  end
end
