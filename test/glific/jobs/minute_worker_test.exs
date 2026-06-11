defmodule Glific.Jobs.MinuteWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  import Mock

  alias Glific.{
    Jobs.MinuteWorker,
    Stats
  }

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
end
