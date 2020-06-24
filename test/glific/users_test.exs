defmodule Glific.UsersTest do
  use Glific.DataCase, async: true

  alias Faker.Phone
  alias Glific.Users

  describe "users" do
    alias Glific.Users.User

    @password "secret1234"

    @valid_attrs %{
      name: "some name",
      phone: "some phone",
      password: @password,
      password_confirmation: @password
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
    @update_attrs %{
      name: "some updated name",
      phone: "some updated phone",
      password: @password,
      password_confirmation: @password
    }
    @invalid_attrs %{
      name: nil,
      phone: nil,
      password: nil,
      password_confirmation: nil
    }

    def user_fixture(attrs \\ %{}) do
      {:ok, user} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Users.create_user()

      user
    end

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Users.list_users() == [user |> Map.put(:password, nil)]
    end

    test "count_users/0 returns count of all users" do
      _ = user_fixture()
      assert Users.count_users() == 1
      assert Users.count_users(%{filter: %{name: "some name"}}) == 1
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Users.get_user!(user.id) == user |> Map.put(:password, nil)
    end

    test "create_user/1 with valid data creates a user" do
      assert {:ok, %User{} = user} = Users.create_user(@valid_attrs)
      assert user.name == "some name"
      assert user.phone == "some phone"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Users.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()

      assert {:ok, %User{} = user} = Users.update_user(user, @update_attrs)
      assert user.name == "some updated name"

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
      _c0 = user_fixture(@valid_attrs)
      _c1 = user_fixture(@valid_attrs_1)
      _c2 = user_fixture(@valid_attrs_2)
      _c3 = user_fixture(@valid_attrs_3)

      assert length(Users.list_users()) == 4
    end

    test "list_users/1 with multiple users sorted" do
      c0 = user_fixture(@valid_attrs)
      c1 = user_fixture(@valid_attrs_1)
      c2 = user_fixture(@valid_attrs_2)
      c3 = user_fixture(@valid_attrs_3)

      c0_pr = c0 |> Map.put(:password, nil)
      c1_pr = c1 |> Map.put(:password, nil)
      c2_pr = c2 |> Map.put(:password, nil)
      c3_pr = c3 |> Map.put(:password, nil)

      cs = Users.list_users(%{opts: %{order: :asc}})
      assert [c0_pr, c1_pr, c2_pr, c3_pr] == cs

      cs = Users.list_users(%{opts: %{order: :desc}})
      assert [c3_pr, c2_pr, c1_pr, c0_pr] == cs
    end

    test "list_users/1 with multiple users filtered" do
      _c0 = user_fixture(@valid_attrs)
      c1 = user_fixture(@valid_attrs_1)
      _c2 = user_fixture(@valid_attrs_2)
      c3 = user_fixture(@valid_attrs_3)

      cs = Users.list_users(%{opts: %{order: :asc}, filter: %{phone: "some phone 3"}})
      assert cs == [c3 |> Map.put(:password, nil)]

      cs = Users.list_users(%{filter: %{phone: "some phone"}})
      assert length(cs) == 4

      cs = Users.list_users(%{opts: %{order: :asc}, filter: %{name: "some name 1"}})
      assert cs == [c1 |> Map.put(:password, nil)]
    end

    test "ensure that creating users with same phone give an error" do
      user_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Users.create_user(@valid_attrs)
    end
  end
end
