defmodule Glific.InteractivesTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Interactives,
    Messages.Interactive
  }

  describe "interactives" do
    @valid_attrs %{
      label: "Quick Reply Test Text",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "type" => "text",
          "text" => "How excited are you for Glific?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Excited"
          },
          %{
            "type" => "text",
            "title" => "Very Excited"
          }
        ]
      }
    }

    @valid_more_attrs %{
      label: "Quick Reply Test Text 2",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "type" => "text",
          "text" => "How was your experience with Glific?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Great"
          },
          %{
            "type" => "text",
            "title" => "Awesome"
          }
        ]
      }
    }

    @update_attrs %{
      label: "Updated Quick Reply label"
    }
    @invalid_attrs %{
      label: nil,
      type: :quick_reply,
      interactive_content: nil
    }

    test "count_interactives/1 returns count of all interactives",
         %{organization_id: _organization_id} = attrs do
      interactive_count = Interactives.count_interactives(%{filter: attrs})
      _ = Fixtures.interactive_fixture(attrs)
      assert Interactives.count_interactives(%{filter: attrs}) == interactive_count + 1

      _ = Fixtures.interactive_fixture(Map.merge(attrs, @valid_more_attrs))
      assert Interactives.count_interactives(%{filter: attrs}) == interactive_count + 2

      assert Interactives.count_interactives(%{
               filter: Map.merge(attrs, %{label: "Quick Reply Test Text 2"})
             }) == 1
    end

    test "get_interactive!/1 returns the interactive with given id", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})
      assert Interactives.get_interactive!(interactive.id) == interactive
    end

    test "create_interactive/1 with valid data creates an interactive message", %{
      organization_id: organization_id
    } do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Interactive{} = interactive} = Interactives.create_interactive(attrs)
      assert interactive.label == "Quick Reply Test Text"
      assert interactive.type == :quick_reply
      assert interactive.organization_id == organization_id
    end

    test "create_interactive/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Interactives.create_interactive(@invalid_attrs)
    end

    test "update_interactive/2 with valid data updates the interactive", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:ok, %Interactive{} = interactive} =
               Interactives.update_interactive(interactive, @update_attrs)

      assert interactive.label == "Updated Quick Reply label"
      assert interactive.type == :quick_reply
    end

    test "update_interactive/2 with invalid data returns error changeset", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:error, %Ecto.Changeset{}} =
               Interactives.update_interactive(interactive, @invalid_attrs)

      assert interactive == Interactives.get_interactive!(interactive.id)
    end

    test "delete_interactive/1 deletes an interactive", %{organization_id: organization_id} do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})
      assert {:ok, %Interactive{}} = Interactives.delete_interactive(interactive)
      assert_raise Ecto.NoResultsError, fn -> Interactives.get_interactive!(interactive.id) end
    end

    test "list_interactives/1 with multiple items",
         %{organization_id: _organization_id} = attrs do
      interactive_count = Interactives.count_interactives(%{filter: attrs})

      interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))
      interactives = Interactives.list_interactives(%{filter: attrs})

      assert length(interactives) == interactive_count + 2

      assert interactive1 in interactives
      assert interactive2 in interactives
    end

    test "list_interactives/1 with multiple items sorted",
         %{organization_id: _organization_id} = attrs do
      interactive_count = Interactives.count_interactives(%{filter: attrs})

      interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(attrs, @valid_more_attrs))
      interactives = Interactives.list_interactives(%{opts: %{order: :asc}, filter: attrs})

      assert length(interactives) == interactive_count + 2

      assert [interactive1, interactive2] ==
               Enum.filter(interactives, fn i -> i.type == :quick_reply end)
    end

    test "list_interactives/1 with items filtered",
         %{organization_id: _organization_id} = attrs do
      _interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))

      interactives =
        Interactives.list_interactives(%{
          opts: %{order: :asc},
          filter: Map.merge(%{label: "Quick Reply Test"}, attrs)
        })

      assert length(interactives) == 1
      [h] = interactives
      assert h == interactive2
    end

    test "list_interactives/1 with interactive type",
         %{organization_id: _organization_id} = attrs do
      interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))

      interactives =
        Interactives.list_interactives(%{
          opts: %{order: :asc},
          filter: Map.merge(%{type: :quick_reply}, attrs)
        })

      assert length(interactives) == 2
      assert interactive1 in interactives
      assert interactive2 in interactives
    end
  end
end
