defmodule Glific.SimulatorTest do
  use Glific.DataCase

  alias Glific.{
    Contacts.Simulator,
    Seeds.SeedsDev,
    Users.User
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_flows(organization)

    Simulator.reset()
    :ok
  end

  test "Ensure cache is initialized to all contacts in free state" %{organization_id: organization_id} = _attrs do
    %{free_simulators: free_simulators, busy_simulators: busy_simulators} = Simulator.state(1)

    # we have 5 simulators in our dev seeder
    assert length(free_simulators) == 5
    assert Enum.empty?(busy_simulators)
  end

  test "Ensure we can request and get 3 simulator contacts, but the 4th is denied" %{organization_id: organization_id} = _attrs do
    1..5
    |> Enum.map(fn x ->
      user = %User{
        organization_id: organization_id,
        id: x,
        fingerprint: Ecto.UUID.generate()
      }

      contact = Simulator.get_simulator(user)
      assert contact != nil
    end)

    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_x = Simulator.get_simulator(user)
    assert contact_x == nil
  end

  test "Ensure we can request and get same simulator contact, for same user id, same fingerprint" %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get_simulator(user)
    assert contact_1 != nil

    contact_2 = Simulator.get_simulator(user)
    assert contact_2 != nil

    assert contact_2 == contact_1
  end

  test "Ensure we can request and get different simulator contact, for same user id, different fingerprint" %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get_simulator(user)
    assert contact_1 != nil

    contact_2 = Simulator.get_simulator(Map.put(user, :fingerprint, Ecto.UUID.generate()))
    assert contact_2 != nil

    assert contact_2 != contact_1
  end

  test "Ensure that when we get and release a simulator the cache returns to its original state" %{organization_id: organization_id} = _attrs do
    cache = Simulator.state(1)

    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get_simulator(user)
    assert contact_1 != nil

    Simulator.release_simulator(user)

    assert cache == Simulator.state(1)
  end

  test "Ensure cache is initialized to all flows in free state" %{organization_id: organization_id} = _attrs do
    %{free_flows: free_flows, busy_flows: busy_flows} = Simulator.state(1)

    # we have 13 flows in our dev seeder
    assert length(free_flows) == 13
    assert Enum.empty?(busy_flows)
  end

  test "Ensure that when we get and release a flow the cache returns to its original state" %{organization_id: organization_id} = _attrs do
    cache = Simulator.state(1)

    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get_flow(user, 1)
    assert contact_1 != nil

    Simulator.release_flow(user)

    assert cache == Simulator.state(1)
  end

  test "Ensure we can request and get different flow, for same user id, different fingerprint" %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_1 = Simulator.get_flow(user, 1)
    assert flow_1 != nil

    flow_2 = Simulator.get_flow(Map.put(user, :fingerprint, Ecto.UUID.generate()), 2)
    assert flow_2 != nil

    assert flow_2 != flow_1
  end

  test "Ensure we can request and get different flow, and on release the number of available flows always remain same",
       %{organization_id: organization_id} = _attrs do
    %{free_flows: free_flows} = Simulator.state(1)
    count_free_flow = length(free_flows)

    user_1 = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_1 = Simulator.get_flow(user_1, 1)
    assert flow_1 != nil

    user_2 = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_2 = Simulator.get_flow(user_2, 2)
    assert flow_2 != nil

    Simulator.release_flow(user_1)
    Simulator.release_flow(user_2)
    %{free_flows: free_flows} = Simulator.state(1)
    new_count_free_flows = length(free_flows)
    assert count_free_flow == new_count_free_flows
  end
end
