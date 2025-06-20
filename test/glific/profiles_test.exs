defmodule Glific.ProfilesTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Profiles,
    Profiles.Profile,
    Repo
  }

  describe "profiles" do
    import Glific.Fixtures

    @invalid_attrs %{name: nil, type: 1}

    @valid_attrs %{
      "name" => "profile 1",
      "type" => "pro",
      "is_default" => true
    }

    @valid_attrs_1 %{
      "name" => "profile 2",
      "contact_id" => 2
    }

    @valid_attrs_2 %{
      "name" => "profile 3",
      "type" => "student",
      "is_active" => false
    }

    test "get_profile!/1 returns the profile with given id" do
      profile = profile_fixture()
      assert Profiles.get_profile!(profile.id) == profile
    end

    test "list_profiles/1 with multiple profiles filtered" do
      _p1 = profile_fixture(@valid_attrs)
      _p2 = profile_fixture(@valid_attrs_1)
      _p3 = profile_fixture(@valid_attrs_2)

      # fliter by name
      [profile | _] = Profiles.list_profiles(%{filter: %{name: "profile 1"}})
      assert profile.name == "profile 1"

      # If no filter is given it will return all the profile
      profile2 = Profiles.list_profiles(%{})
      assert Enum.count(profile2) == 4

      # filter by contact_id
      profile3 = Profiles.list_profiles(%{filter: %{contact_id: 1}})
      assert Enum.count(profile3) == 1

      # filter by active status
      profile4 = Profiles.list_profiles(%{filter: %{is_active: false}})
      assert Enum.count(profile4) == 1

      # filter by active status and sorts default profile first
      profile4 =
        Profiles.list_profiles(%{
          filter: %{is_active: true},
          opts: %{order: :desc, order_with: :is_default}
        })

      assert Enum.count(profile4) == 3
      assert [%Profile{is_default: true} | _] = profile4
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

      {:ok, updated_contact} = Profiles.switch_profile(contact, "1")
      contact = Repo.preload(updated_contact, [:active_profile])
      current_active_profile_id = contact.active_profile_id
      assert is_nil(current_active_profile_id) == false

      # updating with wrong index
      {:error, updated_contact} = Profiles.switch_profile(contact, "some index")

      assert updated_contact.active_profile_id == current_active_profile_id
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

      # Switched to profile 2
      {:ok, contact_with_profile_2} =
        Contacts.get_contact!(contact.id)
        |> Profiles.switch_profile("2")

      assert contact_with_profile_2.active_profile_id == new_profile.id
      assert contact_with_profile_2.active_profile.name == "Profile 2"
    end

    test "deactivate_profile doesn't deactivate default profile",
         attrs do
      {:ok, contact} =
        Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Deactivate Profile Flow"})

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_uuid: flow.uuid,
          flow_id: flow.id,
          flow: flow,
          organization_id: flow.organization_id,
          uuid_map: flow.uuid_map
        })

      context = Repo.preload(context, [:flow, :contact])

      action = %Action{
        id: nil,
        type: "set_contact_profile",
        value: %{"name" => "profile2", "type" => "parent"},
        profile_type: "Create Profile"
      }

      # This will update the contact's first profile to default profile
      Profiles.handle_flow_action(:create_profile, context, action)

      {:ok, default_profile} = Repo.fetch_by(Profile, %{contact_id: contact.id, is_default: true})

      action = %Action{
        id: nil,
        value: "1",
        type: "set_contact_profile",
        profile_type: "Deactivate Profile"
      }

      {_updated_context, message} =
        Profiles.handle_flow_action(:deactivate_profile, context, action)

      {:ok, profile} = Repo.fetch_by(Profile, %{id: default_profile.id})

      # Default profile doesn't get deactivated
      assert profile.is_active == true
      assert message.body == "Success"

      # failure case
      params = %{
        "name" => "Profile 3",
        "type" => "student",
        "contact_id" => contact.id
      }

      profile = Fixtures.profile_fixture(params)
      assert profile.is_active == true

      action = %Action{
        id: nil,
        # random profile index
        value: "x",
        type: "set_contact_profile",
        profile_type: "Deactivate Profile"
      }

      {_updated_context, message} =
        Profiles.handle_flow_action(:deactivate_profile, context, action)

      assert message.body == "Failure"
      assert profile.is_active == true
    end

    test "deactivate_profile should deactivate non-default profile", %{
      organization_id: org_id
    } do
      {:ok, contact} =
        Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: org_id})

      params = %{
        "name" => "Profile 2",
        "type" => "student",
        "contact_id" => contact.id
      }

      non_default_profile1 = Fixtures.profile_fixture(params)
      assert non_default_profile1.is_active == true

      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Deactivate Profile Flow"})

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_uuid: flow.uuid,
          flow_id: flow.id,
          flow: flow,
          organization_id: flow.organization_id,
          uuid_map: flow.uuid_map
        })

      context = Repo.preload(context, [:flow, :contact])

      create_action = %Action{
        id: nil,
        type: "set_contact_profile",
        value: %{"name" => "profile2", "type" => "parent"},
        profile_type: "Create Profile"
      }

      Profiles.handle_flow_action(:create_profile, context, create_action)

      {:ok, non_default_profile2} =
        Repo.fetch_by(Profile, %{name: "profile2", contact_id: contact.id})

      switch_action = %Action{
        id: nil,
        type: "set_contact_profile",
        value: "3",
        profile_type: "Switch Profile"
      }

      Profiles.handle_flow_action(:switch_profile, context, switch_action)

      {:ok, contact} = Repo.fetch_by(Contact, %{name: "NGO Main Account"})
      assert contact.active_profile_id == non_default_profile2.id

      deactivate_action = %Action{
        id: nil,
        value: "2",
        type: "set_contact_profile",
        profile_type: "Deactivate Profile"
      }

      Profiles.handle_flow_action(:deactivate_profile, context, deactivate_action)

      assert {:ok, %Profile{is_active: false}} =
               Repo.fetch_by(Profile, %{id: non_default_profile1.id})
    end

    test "after deactivating current active profile of the user, should switch back to the default profile for the user",
         %{
           organization_id: org_id
         } do
      fetch_contact = fn name ->
        Repo.fetch_by(Contact, %{name: name, organization_id: org_id})
      end

      fetch_profile = fn params ->
        Repo.fetch_by(Profile, Map.put(params, :organization_id, org_id))
      end

      {:ok, contact} = fetch_contact.("NGO Main Account")
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Multiple Profile Creation Flow"})

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_uuid: flow.uuid,
          flow_id: flow.id,
          flow: flow,
          organization_id: flow.organization_id,
          uuid_map: flow.uuid_map
        })

      context = Repo.preload(context, [:flow, :contact])

      create_action = %Action{
        id: nil,
        type: "set_contact_profile",
        value: %{"name" => "profile2", "type" => "parent"},
        profile_type: "Create Profile"
      }

      Profiles.handle_flow_action(:create_profile, context, create_action)

      indexed_profiles = Profiles.get_indexed_profile(contact)

      {profile2, profile2_index} =
        Enum.find(indexed_profiles, fn {profile, _index} -> profile.name == "profile2" end)

      switch_action = %Action{
        id: nil,
        type: "set_contact_profile",
        value: "#{profile2_index}",
        profile_type: "Switch Profile"
      }

      Profiles.handle_flow_action(:switch_profile, context, switch_action)

      {:ok, contact} = fetch_contact.("NGO Main Account")
      assert contact.active_profile_id == profile2.id

      deactivate_action = %Action{
        id: nil,
        value: "#{profile2_index}",
        type: "set_contact_profile",
        profile_type: "Deactivate Profile"
      }

      context = Repo.preload(context, [:contact], force: true)
      Profiles.handle_flow_action(:deactivate_profile, context, deactivate_action)

      {:ok, default_profile} = fetch_profile.(%{is_default: true})
      {:ok, contact} = fetch_contact.("NGO Main Account")
      assert contact.active_profile_id == default_profile.id
    end

    test "after deactivating a profile other than the current active profile, the user's profile should not be switched",
         %{
           organization_id: org_id
         } do
      fetch_contact = fn name ->
        Repo.fetch_by(Contact, %{name: name, organization_id: org_id})
      end

      fetch_profile = fn params ->
        Repo.fetch_by(Profile, Map.put(params, :organization_id, org_id))
      end

      {:ok, contact} = fetch_contact.("NGO Main Account")
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Multiple Profile Creation Flow"})

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_uuid: flow.uuid,
          flow_id: flow.id,
          flow: flow,
          organization_id: flow.organization_id,
          uuid_map: flow.uuid_map
        })

      context = Repo.preload(context, [:flow, :contact])

      profile_args = [
        %{"name" => "profile1", "type" => "parent"},
        %{"name" => "profile2", "type" => "student"}
      ]

      for args <- profile_args do
        action = %Action{
          id: nil,
          type: "set_contact_profile",
          value: args,
          profile_type: "Create Profile"
        }

        Profiles.handle_flow_action(:create_profile, context, action)
      end

      indexed_profiles = Profiles.get_indexed_profile(contact)

      {_profile1, profile1_index} =
        Enum.find(indexed_profiles, fn {profile, _index} -> profile.name == "profile1" end)

      {profile2, profile2_index} =
        Enum.find(indexed_profiles, fn {profile, _index} -> profile.name == "profile2" end)

      switch_action = %Action{
        id: nil,
        type: "set_contact_profile",
        value: "#{profile2_index}",
        profile_type: "Switch Profile"
      }

      Profiles.handle_flow_action(:switch_profile, context, switch_action)

      {:ok, contact} = fetch_contact.("NGO Main Account")
      assert contact.active_profile_id == profile2.id

      action = %Action{
        id: nil,
        value: "#{profile1_index}",
        type: "set_contact_profile",
        profile_type: "Deactivate Profile"
      }

      context = Repo.preload(context, [:contact], force: true)
      Profiles.handle_flow_action(:deactivate_profile, context, action)

      {:ok, contact} = fetch_contact.("NGO Main Account")
      assert contact.active_profile_id == profile2.id

      assert {:ok, %Profile{is_active: false}} = fetch_profile.(%{name: "profile1"})
    end
  end

  test "handle_flow_action/3 creates both a default profile with contact's details and a new profile" <>
         "for the contact that doesn't have a default profile",
       attrs do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

    contact =
      contact
      |> Ecto.Changeset.change(fields: %{"collection" => "collection", "name" => "test"})
      |> Repo.update!()

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Multiple Profile Creation Flow"})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_uuid: flow.uuid,
        flow_id: flow.id,
        flow: flow,
        organization_id: flow.organization_id,
        uuid_map: flow.uuid_map
      })

    context = Repo.preload(context, [:flow, :contact])
    Repo.delete_all(from(p in Profile, where: p.contact_id == ^contact.id))

    action = %Action{
      id: nil,
      type: "set_contact_profile",
      value: %{"name" => "profile2", "type" => "parent"},
      profile_type: "Create Profile"
    }

    Profiles.handle_flow_action(:create_profile, context, action)

    {:ok, default_profile} =
      Repo.fetch_by(Profile, %{name: contact.name, organization_id: attrs.organization_id})

    assert default_profile.is_default == true
    assert default_profile.fields == %{"collection" => "collection", "name" => "test"}

    profiles =
      Profile
      |> where([p], p.contact_id == ^contact.id and p.organization_id == ^attrs.organization_id)
      |> Repo.all()

    assert length(profiles) == 2

    # if user again creates a new profile the default profile shouldn't be created
    action = %Action{
      id: nil,
      type: "set_contact_profile",
      value: %{"name" => "profile3", "type" => "student"},
      profile_type: "Create Profile"
    }

    Profiles.handle_flow_action(:create_profile, context, action)

    profiles =
      Profile
      |> where([p], p.contact_id == ^contact.id and p.organization_id == ^attrs.organization_id)
      |> Repo.all()

    assert length(profiles) == 3
  end

  test "handle_flow_action/3 sets oldest profile as the default profile and creates a new profile" <>
         "for the contact that doesn't have a default profile",
       attrs do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

    contact =
      contact
      |> Ecto.Changeset.change(fields: %{"collection" => "collection", "name" => "test"})
      |> Repo.update!()

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Multiple Profile Creation Flow"})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_uuid: flow.uuid,
        flow_id: flow.id,
        flow: flow,
        organization_id: flow.organization_id,
        uuid_map: flow.uuid_map
      })

    context = Repo.preload(context, [:flow, :contact])
    Repo.delete_all(from(p in Profile, where: p.contact_id == ^contact.id))

    {:ok, oldest_profile} =
      Profiles.create_profile(%{
        name: "User",
        fields: %{name: %{type: "string", label: "Name", value: "User"}},
        is_default: false,
        contact_id: contact.id,
        organization_id: attrs.organization_id,
        language_id: contact.language_id
      })

    action = %Action{
      id: nil,
      type: "set_contact_profile",
      value: %{"name" => "profile2", "type" => "parent"},
      profile_type: "Create Profile"
    }

    Profiles.handle_flow_action(:create_profile, context, action)

    {:ok, default_profile} =
      Repo.fetch_by(Profile, %{
        contact_id: contact.id,
        organization_id: attrs.organization_id,
        is_default: true
      })

    assert default_profile.id == oldest_profile.id
    assert default_profile.is_default

    assert default_profile.fields == %{
             "name" => %{"type" => "string", "label" => "Name", "value" => "User"}
           }

    profiles =
      Profile
      |> where([p], p.contact_id == ^contact.id and p.organization_id == ^attrs.organization_id)
      |> Repo.all()

    assert length(profiles) == 2

    # if user again creates a new profile the default profile shouldn't be created
    action = %Action{
      id: nil,
      type: "set_contact_profile",
      value: %{"name" => "profile3", "type" => "student"},
      profile_type: "Create Profile"
    }

    Profiles.handle_flow_action(:create_profile, context, action)

    profiles =
      Profile
      |> where([p], p.contact_id == ^contact.id and p.organization_id == ^attrs.organization_id)
      |> Repo.all()

    assert length(profiles) == 3
  end

  test "creating a new profile should not switch to the new profile", attrs do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: attrs.organization_id})

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Multiple Profile Creation Flow"})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_uuid: flow.uuid,
        flow_id: flow.id,
        flow: flow,
        organization_id: flow.organization_id,
        uuid_map: flow.uuid_map
      })

    context = Repo.preload(context, [:flow, :contact])

    action = %Action{
      id: nil,
      type: "set_contact_profile",
      value: %{"name" => "profile2", "type" => "parent"},
      profile_type: "Create Profile"
    }

    Profiles.handle_flow_action(:create_profile, context, action)

    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: 1})

    default_profile = Repo.get_by(Profile, contact_id: context.contact.id, is_default: true)

    assert contact.active_profile_id == default_profile.id
  end
end
