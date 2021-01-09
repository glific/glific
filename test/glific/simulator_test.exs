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

    Simulator.init_cache(organization.id)
    :ok
  end

  test "Ensure cache is initialized to all contacts in free state" do
    %{free: free, busy: busy} = Simulator.get_cache()

    # we have 3 simulators in our dev seeder
    assert length(free) == 3
    assert Enum.count(busy) == 0
  end

  test "Ensure we can request anf get 3 simulator contacts, but the 4th is denied" do
    contact_1 = Simulator.get_simulator(1)
    assert contact_1 != nil

    contact_2 = Simulator.get_simulator(2)
    assert contact_2 != nil

    contact_3 = Simulator.get_simulator(3)
    assert contact_3 != nil

    contact_4 = Simulator.get_simulator(4)
    assert contact_4 == nil
  end

  test "Ensure we can request and get same simulator contact, for same user id" do
    contact_1 = Simulator.get_simulator(1)
    assert contact_1 != nil

    contact_2 = Simulator.get_simulator(1)
    assert contact_2 != nil

    assert contact_2 == contact_1
  end

  test "Ensure that when we get and release a simulator the cache returns to its original state" do
    cache = Simulator.get_cache()
    contact_1 = Simulator.get_simulator(1)
    assert contact_1 != nil

    Simulator.release_simulator(1)

    assert cache == Simulator.get_cache()
  end
end
