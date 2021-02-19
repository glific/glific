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

    Simulator.reset()
    :ok
  end

  test "Ensure cache is initialized to all contacts in free state" do
    %{free: free, busy: busy} = Simulator.state(1)

    # we have 5 simulators in our dev seeder
    assert length(free) == 5
    assert Enum.empty?(busy)
  end

  test "Ensure we can request and get 3 simulator contacts, but the 4th is denied" do
    1..5
    |> Enum.map(fn x ->
      user = %User{
        organization_id: 1,
        id: x,
        fingerprint: Ecto.UUID.generate()
      }

      contact = Simulator.get(user)
      assert contact != nil
    end)

    user = %User{
      organization_id: 1,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_x = Simulator.get(user)
    assert contact_x == nil
  end

  test "Ensure we can request and get same simulator contact, for same user id, same fingerprint" do
    user = %User{
      organization_id: 1,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get(user)
    assert contact_1 != nil

    contact_2 = Simulator.get(user)
    assert contact_2 != nil

    assert contact_2 == contact_1
  end

  test "Ensure we can request and get different simulator contact, for same user id, different fingerprint" do
    user = %User{
      organization_id: 1,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get(user)
    assert contact_1 != nil

    contact_2 = Simulator.get(Map.put(user, :fingerprint, Ecto.UUID.generate()))
    assert contact_2 != nil

    assert contact_2 != contact_1
  end

  test "Ensure that when we get and release a simulator the cache returns to its original state" do
    cache = Simulator.state(1)

    user = %User{
      organization_id: 1,
      id: 6,
      fingerprint: Ecto.UUID.generate()
    }

    contact_1 = Simulator.get(user)
    assert contact_1 != nil

    Simulator.release(user)

    assert cache == Simulator.state(1)
  end
end
