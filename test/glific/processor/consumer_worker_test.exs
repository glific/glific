defmodule Glific.Processor.ConsumerWorkerTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Partners,
    Processor.ConsumerWorker,
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
  end
end
