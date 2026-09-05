defmodule Glific.Users.RolesTest do
  use ExUnit.Case, async: true

  alias Glific.Users.Roles

  describe "rank/1" do
    test "orders the hierarchy" do
      assert Roles.rank(:glific_admin) > Roles.rank(:admin)
      assert Roles.rank(:admin) > Roles.rank(:manager)
      assert Roles.rank(:manager) > Roles.rank(:staff)
      assert Roles.rank(:staff) > Roles.rank(:none)
    end

    test "an unknown role ranks lowest so comparisons fail closed" do
      assert Roles.rank(:not_a_role) == 0
      assert Roles.rank("Custom Role") == 0
      assert Roles.rank(nil) == 0
    end

    test "accepts the seeded labels, whatever the separator or case" do
      for label <- ["Glific_admin", "Glific admin", "glific_admin", "GLIFIC ADMIN"] do
        assert Roles.rank(label) == Roles.rank(:glific_admin)
      end

      assert Roles.rank("No access") == Roles.rank(:none)
    end

    # the :role_label scalar turns GraphQL input into a downcased atom, so an aliased
    # spelling reaches us as :"glific admin" rather than :glific_admin
    test "resolves aliased atoms, not just aliased strings" do
      for role <- [:"glific admin", :glific_admin, :"GLIFIC ADMIN"] do
        assert Roles.rank(role) == Roles.rank(:glific_admin)
      end

      assert Roles.rank(:"no access") == Roles.rank(:none)
      refute Roles.can_grant_roles?([:manager], [:"glific admin"])
      refute Roles.can_grant_roles?([:admin], [:"glific admin"])
    end
  end

  describe "highest_rank/1" do
    test "uses the maximum, not the first element" do
      assert Roles.highest_rank([:staff, :glific_admin]) == Roles.rank(:glific_admin)
      assert Roles.highest_rank([:glific_admin, :staff]) == Roles.rank(:glific_admin)
    end

    test "an empty or unexpected list ranks lowest" do
      assert Roles.highest_rank([]) == 0
      assert Roles.highest_rank(nil) == 0
    end
  end

  describe "can_manage_user?/2" do
    test "cannot reach up the hierarchy" do
      refute Roles.can_manage_user?([:manager], [:admin])
      refute Roles.can_manage_user?([:manager], [:glific_admin])
      refute Roles.can_manage_user?([:staff], [:manager])
    end

    test "peers and lower ranks are manageable" do
      assert Roles.can_manage_user?([:admin], [:admin])
      assert Roles.can_manage_user?([:manager], [:staff])
      assert Roles.can_manage_user?([:glific_admin], [:admin])
    end

    test "role stacking does not hide a high-ranked target" do
      refute Roles.can_manage_user?([:manager], [:staff, :glific_admin])
    end
  end

  describe "can_grant_roles?/2" do
    test "nobody may grant a role above their own" do
      refute Roles.can_grant_roles?([:manager], [:glific_admin])
      refute Roles.can_grant_roles?([:manager], [:admin])
      refute Roles.can_grant_roles?([:admin], [:glific_admin])
    end

    test "role stacking cannot smuggle a higher role past the check" do
      refute Roles.can_grant_roles?([:manager], [:staff, :glific_admin])
      refute Roles.can_grant_roles?([:manager], ["Staff", "Glific_admin"])
    end

    test "granting at or below your own rank is allowed" do
      assert Roles.can_grant_roles?([:manager], [:staff])
      assert Roles.can_grant_roles?([:manager], [:manager])
      assert Roles.can_grant_roles?([:glific_admin], [:glific_admin])
    end

    test "an empty request is a no-op" do
      assert Roles.can_grant_roles?([:staff], [])
    end
  end

  describe "reserved/1" do
    test "maps every seeded label to its legacy role" do
      assert Roles.reserved("Admin") == :admin
      assert Roles.reserved("Manager") == :manager
      assert Roles.reserved("Staff") == :staff
      assert Roles.reserved("No access") == :none
      assert Roles.reserved("Glific_admin") == :glific_admin
    end

    test "a custom role is not reserved, so it grants no legacy privilege" do
      assert Roles.reserved("Content Reviewer") == nil
      assert Roles.reserved(nil) == nil
    end
  end
end
