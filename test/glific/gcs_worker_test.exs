defmodule Glific.GcsWorkerTest do
  use GlificWeb.ConnCase
  use Oban.Testing, repo: Glific.Repo
  import Mock
  import Ecto.Query

  alias Glific.{
    Fixtures,
    GCS,
    GCS.GcsWorker,
    Jobs,
    Mails.MailLog,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    valid_attrs = %{
      shortcode: "google_cloud_storage",
      secrets: %{
        "bucket" => "mock-bucket-name",
        "service_account" =>
          Jason.encode!(%{
            project_id: "DEFAULT PROJECT ID",
            private_key_id: "DEFAULT API KEY",
            client_email: "DEFAULT CLIENT EMAIL",
            private_key: "DEFAULT PRIVATE KEY"
          })
      },
      is_active: true,
      organization_id: 1
    }

    {:ok, _credential} = Partners.create_credential(valid_attrs)
    :ok
  end

  test "upload_media/3", attrs do
    Application.put_env(:waffle, :token_fetcher, Glific.GCS)

    body = %{
      error: "invalid_grant",
      error_description: "Invalid grant: account not found"
    }

    body = Jason.encode!(body)

    err_response = """
    unexpected status 400 from Google

    #{body}
    """

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:error, RuntimeError.exception(err_response)}
      end
    ) do
      Glific.Caches.remove(attrs.organization_id, [{:provider_token, "google_cloud_storage"}])

      assert nil ==
               Partners.get_goth_token(attrs.organization_id, "google_cloud_storage")
    end
  end

  test "perform_periodic/2, queuing only media_ids not older than a month", attrs do
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      GCS.insert_gcs_jobs(attrs.organization_id)

      _m1 =
        Fixtures.message_media_fixture(%{
          organization_id: attrs.organization_id
        })
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second),
          updated_at: DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second)
        })
        |> Repo.update()

      _m2 =
        Fixtures.message_media_fixture(%{
          organization_id: attrs.organization_id
        })
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second),
          updated_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second)
        })
        |> Repo.update()

      assert :ok = GcsWorker.perform_periodic(attrs.organization_id, %{phase: "incremental"})
      assert_enqueued(worker: GcsWorker, prefix: "global")

      # We are only concerned about how many jobs queued, since else we have to
      # mock a lot to get this to success.
      assert %{success: 0, failure: 1, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :gcs)
    end
  end

  test "perform_periodic/2, queuing only media_ids not older than a month, unsynced", attrs do
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      GCS.insert_gcs_jobs(attrs.organization_id)

      _m1 =
        Fixtures.message_media_fixture(%{
          organization_id: attrs.organization_id
        })
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second),
          updated_at: DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second)
        })
        |> Repo.update()

      _m2 =
        Fixtures.message_media_fixture(%{
          organization_id: attrs.organization_id
        })
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second),
          updated_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second)
        })
        |> Repo.update()

      assert :ok = GcsWorker.perform_periodic(attrs.organization_id, %{phase: "unsynced"})
      # Because the jobs media_id should be less than the incremental media_id (which is also 0)
      refute_enqueued(worker: GcsWorker, prefix: "global")
    end
  end

  test "perform_periodic/2, sweeping from start on every night for unsynced media_ids", attrs do
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      GCS.insert_gcs_jobs(attrs.organization_id)

      _m1 =
        Fixtures.message_media_fixture(%{
          organization_id: attrs.organization_id
        })
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second),
          updated_at: DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second)
        })
        |> Repo.update()

      media_ids =
        for _i <- 0..5 do
          Fixtures.message_media_fixture(%{
            organization_id: attrs.organization_id
          })
        end

      assert :ok = GcsWorker.perform_periodic(attrs.organization_id, %{phase: "incremental"})
      assert_enqueued(worker: GcsWorker, prefix: "global")
      # Because the file count  limit is 5 by default
      assert %{success: 0, failure: 5, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :gcs)

      assert :ok = GcsWorker.perform_periodic(attrs.organization_id, %{phase: "unsynced"})

      # since it will be less than the "incremental" media_id
      assert %{success: 0, failure: 4, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :gcs)

      assert :ok = GcsWorker.perform_periodic(attrs.organization_id, %{phase: "unsynced"})

      # When we run unsynced again after few mins, we see that no more jobs are
      # enqueued, this is due to the media_id pointer is ahead and we don't look
      # backwards. This is intended as once the nightly job starts then its incremental
      assert %{success: 0, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :gcs)

      unsynced_gcs_job = Jobs.get_gcs_job(attrs.organization_id, "unsynced")

      Ecto.Changeset.change(unsynced_gcs_job, %{
        updated_at: DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second)
      })
      |> Repo.update()

      # Above we have changed the updated_at of unsynced job's update to a day ago to simulate
      # the start of a nigthly sync job. We sweep from the start (>= last 1 month) to
      # find any pending unsynced jobs.
      assert :ok = GcsWorker.perform_periodic(attrs.organization_id, %{phase: "unsynced"})

      assert %{success: 0, failure: 4, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :gcs)

      # Tests for adding gcs_error for message_media
      [media_id | _] = media_ids
      media = %{"id" => media_id.id, "sync_phase" => "unsynced"}
      assert {1, _} = GcsWorker.add_message_media_error(media, "GCSWORKER failed")

      media = %{"id" => media_id.id, "sync_phase" => "incremental"}
      assert is_nil(GcsWorker.add_message_media_error(media, "GCSWORKER failed"))

      assert :ok = GCS.send_internal_media_sync_report()

      assert %MailLog{content: content} =
               MailLog
               |> where([ml], ml.category == "media_sync_report")
               |> Repo.one()

      # We ignore CCing support for this
      refute String.contains?(content["data"], ["support@glific.org"])
    end
  end
end
