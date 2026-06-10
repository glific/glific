defmodule Glific.Jobs.MinuteWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  import Mock

  alias Glific.{
    Jobs.MinuteWorker,
    Stats
  }

  # ---------------------------------------------------------------------------
  # "stats" branch — Appsignal.CheckIn.cron/2 wrapping
  # ---------------------------------------------------------------------------

  describe "stats job" do
    test "calls Appsignal.CheckIn.cron/2 with the correct identifier" do
      with_mock Appsignal.CheckIn,
                [:passthrough],
                cron: fn identifier, fun ->
                  send(self(), {:checkin_called, identifier})
                  fun.()
                end do
        assert :ok = perform_job(MinuteWorker, %{"job" => "stats"})

        assert_received {:checkin_called, "glific_stats_hourly"}
      end
    end

    test "Stats.generate_stats/2 is invoked inside the check-in wrapper" do
      test_pid = self()

      with_mock Appsignal.CheckIn,
                [:passthrough],
                cron: fn _identifier, fun ->
                  fun.()
                end do
        with_mock Stats, [:passthrough],
                  generate_stats: fn org_ids, since_start ->
                    send(test_pid, {:generate_stats_called, org_ids, since_start})
                    :ok
                  end do
          assert :ok = perform_job(MinuteWorker, %{"job" => "stats"})

          assert_received {:generate_stats_called, [], false}
        end
      end
    end

    test "returns :ok when the stats job completes without error" do
      with_mock Appsignal.CheckIn,
                [:passthrough],
                cron: fn _identifier, fun -> fun.() end do
        assert :ok = perform_job(MinuteWorker, %{"job" => "stats"})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Other branches — Appsignal.CheckIn.cron/2 must NOT be called
  # ---------------------------------------------------------------------------

  describe "bigquery job" do
    test "does not call Appsignal.CheckIn.cron/2" do
      with_mock Appsignal.CheckIn, [:passthrough], cron: fn _id, _fun -> :ok end do
        # perform_job returns :ok for bigquery (Partners.perform_all handles empty services)
        perform_job(MinuteWorker, %{"job" => "bigquery"})

        refute called(Appsignal.CheckIn.cron(:_, :_))
      end
    end
  end

  describe "gcs job" do
    test "does not call Appsignal.CheckIn.cron/2" do
      with_mock Appsignal.CheckIn, [:passthrough], cron: fn _id, _fun -> :ok end do
        perform_job(MinuteWorker, %{"job" => "gcs"})

        refute called(Appsignal.CheckIn.cron(:_, :_))
      end
    end
  end

  describe "contact_status job" do
    test "does not call Appsignal.CheckIn.cron/2" do
      with_mock Appsignal.CheckIn, [:passthrough], cron: fn _id, _fun -> :ok end do
        perform_job(MinuteWorker, %{"job" => "contact_status"})

        refute called(Appsignal.CheckIn.cron(:_, :_))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Check-in identifier correctness — using process message as side-effect
  # ---------------------------------------------------------------------------

  describe "check-in identifier" do
    test "identifier is exactly 'glific_stats_hourly' (not a variant)" do
      with_mock Appsignal.CheckIn,
                [:passthrough],
                cron: fn identifier, fun ->
                  send(self(), {:checkin_identifier, identifier})
                  fun.()
                end do
        assert :ok = perform_job(MinuteWorker, %{"job" => "stats"})

        assert_received {:checkin_identifier, "glific_stats_hourly"}
        refute_received {:checkin_identifier, "glific_stats"}
        refute_received {:checkin_identifier, "stats_hourly"}
      end
    end
  end
end
