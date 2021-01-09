defmodule Glific.SimulatorTest do
  use Glific.DataCase

  alias Glific.{
    Contacts.Simulator,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts(organization)

    Simulator.reset(Simulator)
    :ok
  end

  test "Ensure cache is initialized to all contacts in free state" do
    %{free: free, busy: busy} = Simulator.state(Simulator, 1)

    # we have 3 simulators in our dev seeder
    assert length(free) == 3
    assert Enum.empty?(busy)
  end

  test "Ensure we can request and get 3 simulator contacts, but the 4th is denied" do
    contact_1 = Simulator.get(Simulator, 1, 1)
    assert contact_1 != nil

    contact_2 = Simulator.get(Simulator, 1, 2)
    assert contact_2 != nil

    contact_3 = Simulator.get(Simulator, 1, 3)
    assert contact_3 != nil

    contact_4 = Simulator.get(Simulator, 1, 4)
    assert contact_4 == nil
  end

  test "Ensure we can request and get same simulator contact, for same user id" do
    contact_1 = Simulator.get(Simulator, 1, 1)
    assert contact_1 != nil

    contact_2 = Simulator.get(Simulator, 1, 1)
    assert contact_2 != nil

    assert contact_2 == contact_1
  end

  test "Ensure that when we get and release a simulator the cache returns to its original state" do
    cache = Simulator.state(Simulator, 1)

    contact_1 = Simulator.get(Simulator, 1, 1)
    assert contact_1 != nil

    Simulator.release(Simulator, 1, 1)

    assert cache == Simulator.state(Simulator, 1)
  end
end
