defmodule Glific.GcsWorkerTest do
  alias Glific.Repo
  alias Glific.GCS.GcsWorker
  alias Glific.Fixtures
  use GlificWeb.ConnCase
  use Oban.Pro.Testing, repo: Glific.Repo
  import Mock

  alias Glific.{
    Partners,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
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
      valid_attrs = %{
        shortcode: "google_cloud_storage",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: attrs.organization_id
      }

      Glific.Caches.remove(attrs.organization_id, [{:provider_token, "google_cloud_storage"}])

      {:ok, _credential} = Partners.create_credential(valid_attrs)

      assert nil ==
               Partners.get_goth_token(attrs.organization_id, "google_cloud_storage")
    end
  end

  @tag :gsync
  test "perform_periodic/2, queuing only media_ids not older than a month", attrs do
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
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
end
