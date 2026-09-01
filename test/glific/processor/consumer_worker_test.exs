defmodule Glific.Processor.ConsumerWorkerTest do
  use Glific.DataCase

  import Mock

  alias Glific.{
    Fixtures,
    Partners,
    Processor.ConsumerWorker,
    Processor.ConsumerWorkerMock,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  test "start the genserver", %{organization_id: organization_id} do
    {:ok, worker} = ConsumerWorker.start_link([])

    user = Partners.organization(organization_id).root_user
    message = Fixtures.message_fixture()

    GenServer.call(worker, {message, {organization_id, user}, self()})

    GenServer.cast(worker, {message, {organization_id, user}, self()})
    # this waits for the cast to complete before returning
    _ = :sys.get_state(worker)
  end

  test "start the genserver mock", %{organization_id: organization_id} do
    {:ok, worker} = ConsumerWorkerMock.start_link([])

    user = Partners.organization(organization_id).root_user
    message = Fixtures.message_fixture()

    GenServer.call(worker, {message, {organization_id, user}, self()})

    GenServer.cast(worker, {message, {organization_id, user}, self()})
    # this waits for the cast to complete before returning
    _ = :sys.get_state(worker)
  end

  test "processing a message reports flow_processing_duration tagged by organization_id", %{
    organization_id: organization_id
  } do
    {:ok, worker} = ConsumerWorker.start_link([])

    user = Partners.organization(organization_id).root_user
    message = Fixtures.message_fixture()
    test_pid = self()

    with_mock Appsignal, [:passthrough],
      add_distribution_value: fn name, value, tags ->
        send(test_pid, {:distribution, name, value, tags})
        :ok
      end do
      GenServer.call(worker, {message, {organization_id, user}, self()})
    end

    assert_received {:distribution, "flow_processing_duration", duration, tags}
    assert is_number(duration)
    assert duration >= 0
    assert tags == %{organization_id: organization_id}
  end
end
