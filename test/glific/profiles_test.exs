defmodule Glific.ProfilesTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Profiles,
    Profiles.Profile,
    Repo
  }

  describe "profiles" do
    import Glific.Fixtures

    @invalid_attrs %{name: nil, type: 1}

    @valid_attrs %{
      "name" => "profile 1",
      "type" => "pro"
    }

    @valid_attrs_1 %{
      "name" => "profile 2",
      "contact_id" => 2
    }
    test "get_profile!/1 returns the profile with given id" do
      profile = profile_fixture()
      assert Profiles.get_profile!(profile.id) == profile
    end

    test "list_contacts/1 with multiple profiles filtered" do
      _p1 = profile_fixture(@valid_attrs)
      _p2 = profile_fixture(@valid_attrs_1)

      # fliter by name
      [profile | _] = Profiles.list_profiles(%{filter: %{name: "profile 1"}})
      assert profile.name == "profile 1"

      # If no filter is given it will return all the profile
      profile2 = Profiles.list_profiles(%{})
      assert Enum.count(profile2) == 3

      # filter by contact_id
      profile3 = Profiles.list_profiles(%{filter: %{contact_id: 1}})
      assert Enum.count(profile3) == 1
    end

    test "create_profile/1 with valid data creates a profile" do
      valid_attrs = %{
        name: "some name",
        type: "some type",
        contact_id: 1,
        language_id: 1,
        organization_id: 1,
        fields: %{name: "max"}
      }

      assert {:ok, profile} = Profiles.create_profile(valid_attrs)

      assert profile.name == "some name"
      assert profile.type == "some type"
      assert profile.fields.name == "max"
    end

    test "create_profile/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Profiles.create_profile(@invalid_attrs)
    end

    test "update_profile/2 with valid data updates the profile" do
      profile = profile_fixture()
      update_attrs = %{name: "some updated name", type: "some updated type"}

      assert {:ok, profile} = Profiles.update_profile(profile, update_attrs)
      assert profile.name == "some updated name"
      assert profile.type == "some updated type"
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

    test "get_indexed_profile/1 returns all indexed profile for a contact", attrs do
      {:ok, contact} =
        Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

      profiles = Profiles.get_indexed_profile(contact)
      count_1 = Enum.count(profiles)

      params = %{
        "name" => "Profile 2",
        "type" => "student",
        "contact_id" => contact.id
      }

      Fixtures.profile_fixture(params)

      profiles_2 = Profiles.get_indexed_profile(contact)
      count_2 = Enum.count(profiles_2)
      assert count_2 > count_1
    end

    test "switch_profile/2 switches contact's active profile based on index", attrs do
      {:ok, contact} =
        Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

      assert is_nil(contact.active_profile_id) == true

      updated_contact =
        Profiles.switch_profile(contact, "1")
        |> Repo.preload([:active_profile])

      assert is_nil(updated_contact.active_profile_id) == false

      # updating with wrong index
      updated_contact =
        Profiles.switch_profile(contact, "some index")
        |> Repo.preload([:active_profile])

      assert is_nil(updated_contact.active_profile_id) == true
    end

    test "switch_profile/2 switches contact's active and sync contact fields", attrs do
      {:ok, contact} =
        Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

      # Creating a new profile and switching to second profile
      params = %{
        "name" => "Profile 2",
        "type" => "student",
        "contact_id" => contact.id
      }

      new_profile = Fixtures.profile_fixture(params)

      updated_contact =
        Contacts.get_contact!(contact.id)
        |> Profiles.switch_profile("2")
        |> Profiles.switch_profile("1")
        |> Repo.preload([:active_profile])

      assert updated_contact.active_profile_id == new_profile.id
      assert updated_contact.active_profile.name == "Profile 2"
    end
  end
end
