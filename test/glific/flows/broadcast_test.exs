defmodule Glific.Flows.BroadcastTest do
  use Glific.DataCase

  import ExUnit.CaptureLog

  alias Glific.{Contacts.Contact, Flows.Broadcast}

  setup do
    level = Logger.level()
    Logger.configure(level: :error)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  test "log_task_timeouts/2 logs timed-out contacts and groups as errors with org_id", %{
    organization_id: organization_id
  } do
    log =
      capture_log(fn ->
        Broadcast.log_task_timeouts(
          [
            {:ok, :ok},
            {:exit, {%Contact{id: 11}, :timeout}},
            {:exit, {42, :timeout}},
            {:exit, {%Contact{id: 12}, :killed}}
          ],
          organization_id
        )
      end)

    assert log =~ "org_id=#{organization_id}"
    assert log =~ "Broadcast task timed out for contact_id: 11"
    assert log =~ "Broadcast task timed out for wa_group_id: 42"
    assert log =~ "Broadcast task failed: {:exit, {%Glific.Contacts.Contact{"
    assert log =~ ":killed}}"
    refute log =~ "{:ok, :ok}"
  end
end
