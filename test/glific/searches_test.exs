defmodule Glific.SearchesTest do
  use Glific.DataCase

  alias Glific.Searches

  describe "searches" do
    alias Glific.Searches.SavedSearch

    @valid_attrs %{args: %{}, label: "some label", shortcode: "short"}
    @update_attrs %{args: %{}, label: "some updated label", shortcode: "code"}
    # no shortcode
    @invalid_attrs %{args: nil, label: "fsdf"}
    # no label
    @invalid_attrs_1 %{args: nil, shortcode: "fsdf"}

    def saved_search_fixture(attrs) do
      {:ok, saved_search} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Searches.create_saved_search()

      saved_search
    end

    test "list_saved_searches/1 returns all searches", attrs do
      saved_search = saved_search_fixture(attrs)
      assert saved_search in Searches.list_saved_searches(%{filter: attrs})
    end

    test "count_saved_searches/1 returns count of all saved_searches",
         %{organization_id: organization_id} = attrs do
      saved_searches_count = Searches.count_saved_searches(%{filter: attrs})

      saved_search_fixture(attrs)
      assert Searches.count_saved_searches(%{filter: attrs}) == saved_searches_count + 1

      assert Searches.count_saved_searches(%{
               filter: %{
                 label: "Conversations read but not replied",
                 organization_id: organization_id
               }
             }) == 1
    end

    test "get_saved_search!/1 returns the search with given id", attrs do
      saved_search = saved_search_fixture(attrs)
      assert Searches.get_saved_search!(saved_search.id) == saved_search
    end

    test "create_saved_search/1 with valid data creates a search", attrs do
      assert {:ok, %SavedSearch{} = saved_search} =
               Searches.create_saved_search(Map.merge(attrs, @valid_attrs))

      assert saved_search.args == %{}
      assert saved_search.label == "some label"
    end

    test "create_saved_search/1 with invalid data returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} =
               Searches.create_saved_search(Map.merge(attrs, @invalid_attrs))

      assert {:error, %Ecto.Changeset{}} =
               Searches.create_saved_search(Map.merge(attrs, @invalid_attrs_1))
    end

    test "update_saved_search/2 with valid data updates the saved search", attrs do
      saved_search = saved_search_fixture(attrs)

      assert {:ok, %SavedSearch{} = saved_search} =
               Searches.update_saved_search(saved_search, @update_attrs)

      assert saved_search.args == %{}
      assert saved_search.label == "some updated label"
    end

    test "update_saved_search/2 with invalid data returns error changeset", attrs do
      saved_search = saved_search_fixture(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Searches.update_saved_search(saved_search, @invalid_attrs)

      assert saved_search == Searches.get_saved_search!(saved_search.id)
    end

    test "delete_saved_search/1 deletes the saved search", attrs do
      saved_search = saved_search_fixture(attrs)
      assert {:ok, %SavedSearch{}} = Searches.delete_saved_search(saved_search)
      assert_raise Ecto.NoResultsError, fn -> Searches.get_saved_search!(saved_search.id) end
    end

    test "change_saved_search/1 returns a saved search changeset", attrs do
      saved_search = saved_search_fixture(attrs)
      assert %Ecto.Changeset{} = Searches.change_saved_search(saved_search)
    end
  end
end
