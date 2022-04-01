defmodule Glific.StateTest do
  use Glific.DataCase

  alias Glific.{
    Seeds.SeedsDev,
    State,
    Users.User
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_flows(organization)

    State.reset()
    :ok
  end

  test "Ensure cache is initialized to all contacts in free state" do
    %{simulator: %{free: free_simulators, busy: busy_simulators}} = State.state(1)

    # we have 5 simulators in our dev seeder
    assert length(free_simulators) == 5
    assert Enum.empty?(busy_simulators)
  end

  test "Ensure we can request and get 3 simulator contacts, but the 4th is denied",
       %{organization_id: organization_id} = _attrs do
    1..5
    |> Enum.map(fn x ->
      user = %User{
        organization_id: organization_id,
        id: x,
        fingerprint: Ecto.UUID.generate()
      }

      contact = State.get_simulator(user)
      assert contact != nil
    end)

    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_x = State.get_simulator(user)
    assert contact_x == nil
  end

  test "Ensure we can request and get same simulator contact, for same user id, same fingerprint",
       %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = State.get_simulator(user)
    assert contact_1 != nil

    contact_2 = State.get_simulator(user)
    assert contact_2 != nil

    assert contact_2 == contact_1
  end

  test "Ensure we can request and get different simulator contact, for same user id, different fingerprint",
       %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = State.get_simulator(user)
    assert contact_1 != nil

    contact_2 = State.get_simulator(Map.put(user, :fingerprint, Ecto.UUID.generate()))
    assert contact_2 != nil

    assert contact_2 != contact_1
  end

  test "Ensure that when we get and release a simulator the cache returns to its original state",
       %{organization_id: organization_id} = _attrs do
    cache = State.state(1)

    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = State.get_simulator(user)
    assert contact_1 != nil

    State.release_simulator(user)

    assert cache == State.state(1)
  end

  test "Ensure cache is initialized to all flows in free state" do
    %{flow: %{free: free_flows, busy: busy_flows}} = State.state(1)

    # we have 13 flows in our dev seeder
    assert length(free_flows) == 14
    assert Enum.empty?(busy_flows)
  end

  test "Ensure that when we get and release a flow the cache returns to its original state",
       %{organization_id: organization_id} = _attrs do
    cache = State.state(1)

    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = State.get_flow(user, 1)
    assert contact_1 != nil

    State.release_flow(user)

    assert cache == State.state(1)
  end

  test "Ensure we can request and get different flow, for same user id, different fingerprint",
       %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_1 = State.get_flow(user, 1)
    assert flow_1 != nil

    flow_2 = State.get_flow(Map.put(user, :fingerprint, Ecto.UUID.generate()), 2)
    assert flow_2 != nil

    assert flow_2 != flow_1
  end

  test "Ensure we can request and get same flow, for same user id, same fingerprint",
       %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_1 = State.get_flow(user, 1)
    assert flow_1 != nil

    flow_2 = State.get_flow(user, 1)
    assert flow_2 != nil

    assert flow_2 == flow_1
  end

  test "Ensure we can request and get different flow, for same user id, same fingerprint and previous flow is updated as available flow",
       %{organization_id: organization_id} = _attrs do
    user = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_1 = State.get_flow(user, 1)
    assert flow_1 != nil

    flow_2 = State.get_flow(user, 2)
    assert flow_2 != nil

    %{flow: %{free: free_flows}} = State.state(1)
    assert true == Enum.member?(free_flows, flow_1)
  end

  test "Ensure we can request and get different flow, and on release the number of available flows always remain same",
       %{organization_id: organization_id} = _attrs do
    %{flow: %{free: free_flows}} = State.state(1)
    count_free_flow = length(free_flows)

    user_1 = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_1 = State.get_flow(user_1, 1)
    assert flow_1 != nil

    user_2 = %User{
      organization_id: organization_id,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    flow_2 = State.get_flow(user_2, 2)
    assert flow_2 != nil

    State.release_flow(user_1)
    State.release_flow(user_2)
    %{flow: %{free: free_flows}} = State.state(1)
    new_count_free_flows = length(free_flows)
    assert count_free_flow == new_count_free_flows
  end
end
