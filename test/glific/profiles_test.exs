defmodule Glific.ProfilesTest do
  use Glific.DataCase

  alias Glific.Profiles

  describe "profiles" do
    alias Glific.Profiles.Profile

    import Glific.Fixtures

    @invalid_attrs %{name: nil, profile_type: 1}

    test "get_profile!/1 returns the profile with given id" do
      profile = profile_fixture()
      assert Profiles.get_profile!(profile.id) == profile
    end

    test "create_profile/1 with valid data creates a profile" do
      valid_attrs = %{
        name: "some name",
        profile_type: "some type",
        contact_id: 1,
        language_id: 1,
        organization_id: 1
      }

      assert {:ok, profile} = Profiles.create_profile(valid_attrs)

      assert profile.name == "some name"
      assert profile.profile_type == "some type"
    end

    test "create_profile/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Profiles.create_profile(@invalid_attrs)
    end

    test "update_profile/2 with valid data updates the profile" do
      profile = profile_fixture()
      update_attrs = %{name: "some updated name", profile_type: "some updated type"}

      assert {:ok, profile} = Profiles.update_profile(profile, update_attrs)
      assert profile.name == "some updated name"
      assert profile.profile_type == "some updated type"
    end

    test "update_profile/2 with invalid data returns error changeset" do
      profile = profile_fixture()
      assert {:error, %Ecto.Changeset{}} = Profiles.update_profile(profile, @invalid_attrs)
      assert profile == Profiles.get_profile!(profile.id)
    end

    test "delete_profile/1 deletes the profile" do
      profile = profile_fixture()
      assert {:ok, %Profile{}} = Profiles.delete_profile(profile)
      assert_raise Ecto.NoResultsError, fn -> Profiles.get_profile!(profile.id) end
    end
  end
end
