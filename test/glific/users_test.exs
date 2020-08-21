defmodule Glific.UsersTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Users
  }

  describe "users" do
    alias Glific.Users.User

    @password "secret1234"

    @valid_attrs %{
      name: "some name",
      phone: "some phone",
      password: @password,
      password_confirmation: @password,
      roles: ["admin"]
    }
    @valid_attrs_1 %{
      name: "some name 1",
      phone: "some phone 1",
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_2 %{
      name: "some name 2",
      phone: "some phone 2",
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_3 %{
      name: "some name 3",
      phone: "some phone 3",
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_to_test_order_1 %{
      name: "aaaa name",
      phone: "some phone 4",
      password: @password,
      password_confirmation: @password
    }
    @valid_attrs_to_test_order_2 %{
      name: "zzzz name",
      phone: "some phone 5",
      password: @password,
      password_confirmation: @password
    }
    @update_attrs %{
      name: "some updated name",
      phone: "some updated phone",
      password: @password,
      password_confirmation: @password,
      roles: ["staff", "admin"]
    }
    @invalid_attrs %{
      name: nil,
      phone: nil,
      password: nil,
      password_confirmation: nil
    }

    def user_fixture(attrs \\ %{}) do
      contact = Fixtures.contact_fixture()

      {:ok, user} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Map.put(:contact_id, contact.id)
        |> Users.create_user()

      user
    end

    test "list_users/0 returns all users" do
      users_count = Repo.aggregate(User, :count)

      _user = user_fixture()
      assert length(Users.list_users()) == users_count + 1
    end

    test "count_users/0 returns count of all users" do
      users_count = Repo.aggregate(User, :count)

      _ = user_fixture()

      assert Users.count_users() == users_count + 1
      assert Users.count_users(%{filter: %{name: "some name"}}) == 1
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Users.get_user!(user.id) == user |> Map.put(:password, nil)
    end

    test "create_user/1 with valid data creates a user" do
      contact = Fixtures.contact_fixture()

      valid_attrs = @valid_attrs |> Map.put(:contact_id, contact.id)

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.name == "some name"
      assert user.phone == "some phone"
      assert user.roles == ["Admin"]
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Users.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()

      assert {:ok, %User{} = user} = Users.update_user(user, @update_attrs)
      assert user.name == "some updated name"
      assert user.roles == ["Staff", "Admin"]

      # Check phone doesn't get updated
      assert user.phone == "some phone"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Users.update_user(user, @invalid_attrs)
      assert user |> Map.put(:password, nil) == Users.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Users.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Users.get_user!(user.id) end
    end

    test "list_users/1 with multiple users" do
      users_count = Repo.aggregate(User, :count)

      user_fixture(@valid_attrs)
      user_fixture(@valid_attrs_1)
      user_fixture(@valid_attrs_2)
      user_fixture(@valid_attrs_3)

      assert length(Users.list_users()) == users_count + 4
    end

    test "list_users/1 with multiple users sorted" do
      users_count = Repo.aggregate(User, :count)

      u0 = user_fixture(@valid_attrs_to_test_order_1)
      u1 = user_fixture(@valid_attrs_to_test_order_2)

      u0_pr = u0 |> Map.put(:password, nil)
      u1_pr = u1 |> Map.put(:password, nil)

      assert length(Users.list_users()) == users_count + 2

      [ordered_u0 | _] = Users.list_users(%{opts: %{order: :asc}})
      assert u0_pr == ordered_u0

      [ordered_u1 | _] = Users.list_users(%{opts: %{order: :desc}})
      assert u1_pr == ordered_u1
    end

    test "list_users/1 with multiple users filtered" do
      _u0 = user_fixture(@valid_attrs)
      u1 = user_fixture(@valid_attrs_1)
      _u2 = user_fixture(@valid_attrs_2)
      u3 = user_fixture(@valid_attrs_3)

      cs = Users.list_users(%{opts: %{order: :asc}, filter: %{phone: "some phone 3"}})
      assert cs == [u3 |> Map.put(:password, nil)]

      cs = Users.list_users(%{filter: %{phone: "some phone"}})
      assert length(cs) == 4

      cs = Users.list_users(%{opts: %{order: :asc}, filter: %{name: "some name 1"}})
      assert cs == [u1 |> Map.put(:password, nil)]
    end

    test "ensure that creating users with same phone give an error" do
      contact1 = Fixtures.contact_fixture()
      contact2 = Fixtures.contact_fixture()
      valid_attrs1 = @valid_attrs |> Map.put(:contact_id, contact1.id)
      valid_attrs2 = @valid_attrs |> Map.put(:contact_id, contact2.id)

      Users.create_user(valid_attrs1)
      assert {:error, %Ecto.Changeset{}} = Users.create_user(valid_attrs2)
    end

    test "ensure that creating users with same contact_id gives an error" do
      contact = Fixtures.contact_fixture()
      valid_attrs1 = @valid_attrs |> Map.put(:contact_id, contact.id)
      valid_attrs2 = @valid_attrs_2 |> Map.put(:contact_id, contact.id)

      Users.create_user(valid_attrs1)
      assert {:error, %Ecto.Changeset{}} = Users.create_user(valid_attrs2)
    end
  end
end
