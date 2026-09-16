defmodule Glific.UsersTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Users,
    Users.User
  }

  describe "users" do
    @password "Secret1234!"

    @valid_attrs %{
      name: "some name",
      phone: "some phone",
      language_id: 1,
      email: "some_name@gmail.com",
      consent_for_updates: false,
      password: @password,
      password_confirmation: @password,
      roles: ["admin"]
    }
    @valid_attrs_1 %{
      name: "some name 1",
      phone: "some phone 1",
      consent_for_updates: false,
      email: "some_name1@gmail.com",
      language_id: 1,
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_2 %{
      name: "some name 2",
      phone: "some phone 2",
      email: "some_name2@gmail.com",
      language_id: 1,
      consent_for_updates: false,
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_3 %{
      name: "some name 3",
      phone: "some phone 3",
      email: "some_name3@gmail.com",
      consent_for_updates: false,
      language_id: 1,
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_to_test_order_1 %{
      name: "aaaa name",
      phone: "some phone 4",
      email: "some_name4@gmail.com",
      consent_for_updates: false,
      language_id: 1,
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_to_test_order_2 %{
      name: "zzzz name",
      phone: "some phone 5",
      email: "some_name5@gmail.com",
      consent_for_updates: false,
      language_id: 1,
      password: @password,
      password_confirmation: @password
    }
    @update_attrs %{
      name: "some updated name",
      phone: "some updated phone",
      email: "some_updated_name@gmail.com",
      language_id: 1,
      password: @password,
      password_confirmation: @password,
      consent_for_updates: false,
      roles: [:staff, :admin],
      is_restricted: true
    }
    @invalid_attrs %{
      name: nil,
      phone: nil,
      email: nil,
      language_id: 1,
      password: nil,
      consent_for_updates: false,
      password_confirmation: nil
    }

    def user_fixture(attrs) do
      contact = Fixtures.contact_fixture(attrs)

      {:ok, user} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:organization_id, contact.organization_id)
        |> Users.create_user()

      user
    end

    test "list_users/1 returns all users", %{organization_id: _organization_id} = attrs do
      users_count = Users.count_users(%{filter: attrs})

      _user = user_fixture(attrs)
      assert length(Users.list_users(%{filter: attrs})) == users_count + 1
    end

    test "count_users/1 returns count of all users",
         %{organization_id: _organization_id} = attrs do
      users_count = Users.count_users(%{filter: attrs})
      _ = user_fixture(Map.put(attrs, :name, "A real unique name"))

      assert Users.count_users(%{filter: attrs}) == users_count + 1
      assert Users.count_users(%{filter: Map.merge(attrs, %{name: "A real unique name"})}) == 1
    end

    test "get_user!/1 returns the user with given id",
         %{organization_id: _organization_id} = attrs do
      user = user_fixture(attrs)
      assert Users.get_user!(user.id) == user |> Map.put(:password, nil)
    end

    test "create_user/1 with valid data creates a user",
         %{organization_id: _organization_id} = attrs do
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:organization_id, contact.organization_id)

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.name == "some name"
      assert user.phone == "some phone"
      assert user.email == "some_name@gmail.com"
      assert user.roles == [:admin]
      assert user.consent_for_updates == false
    end

    test "create_user/1 with invalid data returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} = Users.create_user(Map.merge(attrs, @invalid_attrs))
    end

    test "update_user/2 with valid data updates the user", attrs do
      user = user_fixture(attrs)

      assert {:ok, %User{} = user} = Users.update_user(user, @update_attrs)
      assert user.name == "some updated name"
      assert user.email == "some_updated_name@gmail.com"
      assert user.roles == [:staff, :admin]
      assert user.is_restricted == true
      assert user.consent_for_updates == false

      # Check phone doesn't get updated
      assert user.phone == "some phone"
    end

    test "update_user/2 with only a valid name should update the user’s name.", attrs do
      user = user_fixture(attrs)

      assert {:ok, %User{} = user} = Users.update_user(user, %{name: "some updated name"})
      assert user.name == "some updated name"

      # would be great if we can check that the user tokens were deleted
      # but we never create them, so that code does not really run

      # Check phone doesn't get updated
      assert user.phone == "some phone"
      assert user.consent_for_updates == false
    end

    test "update_user/2 with only a valid email should update the user’s email.", attrs do
      user = user_fixture(attrs)

      assert {:ok, %User{} = user} =
               Users.update_user(user, %{email: "some_updated_name@gmail.com"})

      assert user.email == "some_updated_name@gmail.com"
    end

    test "update_user/2 with invalid data returns error changeset", attrs do
      user = user_fixture(attrs)
      assert {:error, %Ecto.Changeset{}} = Users.update_user(user, @invalid_attrs)
      assert user |> Map.put(:password, nil) == Users.get_user!(user.id)
    end

    test "delete_user/1 deletes the user", attrs do
      user = user_fixture(attrs)
      assert {:ok, %User{}} = Users.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Users.get_user!(user.id) end
    end

    test "list_users/1 with multiple users", attrs do
      users_count = Users.count_users(%{filter: attrs})

      user_fixture(Map.merge(attrs, @valid_attrs))
      user_fixture(Map.merge(attrs, @valid_attrs_1))
      user_fixture(Map.merge(attrs, @valid_attrs_2))
      user_fixture(Map.merge(attrs, @valid_attrs_3))

      assert length(Users.list_users(%{filter: attrs})) == users_count + 4
    end

    test "list_users/1 with multiple users sorted", attrs do
      users_count = Users.count_users(%{filter: attrs})

      u0 = user_fixture(Map.merge(attrs, @valid_attrs_to_test_order_1))
      u1 = user_fixture(Map.merge(attrs, @valid_attrs_to_test_order_2))

      u0_pr = u0 |> Map.put(:password, nil)
      u1_pr = u1 |> Map.put(:password, nil)

      assert length(Users.list_users(%{filter: attrs})) == users_count + 2

      [ordered_u0 | _] = Users.list_users(%{opts: %{order: :asc}, filter: attrs})
      assert u0_pr == ordered_u0

      [ordered_u1 | _] = Users.list_users(%{opts: %{order: :desc}, filter: attrs})
      assert u1_pr == ordered_u1
    end

    test "list_users/1 with multiple users filtered", attrs do
      _u0 = user_fixture(Map.merge(attrs, @valid_attrs))
      u1 = user_fixture(Map.merge(attrs, @valid_attrs_1))
      _u2 = user_fixture(Map.merge(attrs, @valid_attrs_2))
      u3 = user_fixture(Map.merge(attrs, @valid_attrs_3))

      cs =
        Users.list_users(%{
          opts: %{order: :asc},
          filter: Map.merge(attrs, %{phone: "some phone 3"})
        })

      assert cs == [u3 |> Map.put(:password, nil)]

      cs = Users.list_users(%{filter: Map.merge(attrs, %{phone: "some phone"})})
      assert length(cs) == 4

      cs =
        Users.list_users(%{
          opts: %{order: :asc},
          filter: Map.merge(attrs, %{name: "some name 1"})
        })

      assert cs == [u1 |> Map.put(:password, nil)]
    end

    test "ensure that creating users with same phone give an error", attrs do
      contact1 = Fixtures.contact_fixture(attrs)
      contact2 = Fixtures.contact_fixture(attrs)

      valid_attrs1 =
        @valid_attrs
        |> Map.put(:contact_id, contact1.id)
        |> Map.put(:organization_id, contact1.organization_id)

      valid_attrs2 =
        @valid_attrs
        |> Map.put(:contact_id, contact2.id)
        |> Map.put(:organization_id, contact2.organization_id)

      Users.create_user(valid_attrs1)
      assert {:error, %Ecto.Changeset{}} = Users.create_user(valid_attrs2)
    end

    test "ensure that creating users with same contact_id gives an error", attrs do
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:organization_id, contact.organization_id)

      Users.create_user(valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Users.create_user(valid_attrs)
    end

    test "ensure when we authenticate a valid and invalid phone, we get nil" do
      assert Users.authenticate(%{"phone" => "1234567890123", "organization_id" => 1}) == nil

      user = user_fixture(@valid_attrs)

      auth_user =
        Users.authenticate(%{
          "phone" => user.phone,
          "organization_id" => 1,
          "password" => @password
        })

      assert auth_user.id == user.id
    end
  end

  test "promoting a user works for first user, for other users it will be No access", attrs do
    user = user_fixture(Map.put(attrs, :roles, [:none]))
    assert user.roles == [:none]

    user = Users.promote_first_user(user)
    assert user.roles == [:admin]
    user = user_fixture(Map.put(@valid_attrs_1, :roles, [:none]))

    assert user.roles == [:none]

    user = Users.promote_first_user(user)
    assert user.roles == [:none]
  end
end
