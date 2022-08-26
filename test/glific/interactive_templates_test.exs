defmodule Glific.InteractiveTemplatesTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates
  }

  describe "interactive_templates" do
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

    test "count_interactive_templates/1 returns count of all interactives",
         %{organization_id: _organization_id} = attrs do
      interactive_count = InteractiveTemplates.count_interactive_templates(%{filter: attrs})
      _ = Fixtures.interactive_fixture(attrs)

      assert InteractiveTemplates.count_interactive_templates(%{filter: attrs}) ==
               interactive_count + 1

      _ = Fixtures.interactive_fixture(Map.merge(attrs, @valid_more_attrs))

      assert InteractiveTemplates.count_interactive_templates(%{filter: attrs}) ==
               interactive_count + 2

      assert InteractiveTemplates.count_interactive_templates(%{
               filter: Map.merge(attrs, %{label: "Quick Reply Test Text 2"})
             }) == 1
    end

    test "get_interactive_template!/1 returns the interactive with given id", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})
      assert InteractiveTemplates.get_interactive_template!(interactive.id) == interactive
    end

    test "fetch_interactive_template/1 returns the interactive_template with given id or returns {:ok, interactive_template} or {:error, any}",
         %{organization_id: organization_id} do
      interactive_template = Fixtures.interactive_fixture(%{organization_id: organization_id})

      {:ok, fetched_interactive_template} =
        InteractiveTemplates.fetch_interactive_template(interactive_template.id)

      assert fetched_interactive_template.label == interactive_template.label
      assert fetched_interactive_template.type == interactive_template.type

      assert fetched_interactive_template.interactive_content ==
               interactive_template.interactive_content
    end

    test "create_interactive_template/1 with valid data creates an interactive message", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      attrs =
        Map.merge(@valid_attrs, %{
          organization_id: organization_id,
          language_id: interactive.language_id
        })

      assert {:ok, %InteractiveTemplate{} = interactive} =
               InteractiveTemplates.create_interactive_template(attrs)

      assert interactive.label == "Quick Reply Test Text"
      assert interactive.type == :quick_reply
      assert interactive.organization_id == organization_id
    end

    test "create_interactive_template/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               InteractiveTemplates.create_interactive_template(@invalid_attrs)
    end

    test "update_interactive_template/2 with valid data updates the interactive", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:ok, %InteractiveTemplate{} = interactive} =
               InteractiveTemplates.update_interactive_template(interactive, @update_attrs)

      assert interactive.label == "Updated Quick Reply label"
      assert interactive.type == :quick_reply
    end

    test "update_interactive_template/2 with invalid data returns error changeset", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:error, %Ecto.Changeset{}} =
               InteractiveTemplates.update_interactive_template(interactive, @invalid_attrs)

      assert interactive == InteractiveTemplates.get_interactive_template!(interactive.id)
    end

    test "delete_interactive_template/1 deletes an interactive", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:ok, %InteractiveTemplate{}} =
               InteractiveTemplates.delete_interactive_template(interactive)

      assert_raise Ecto.NoResultsError, fn ->
        InteractiveTemplates.get_interactive_template!(interactive.id)
      end
    end

    test "list_interactives/1 with multiple items",
         %{organization_id: _organization_id} = attrs do
      interactive_count = InteractiveTemplates.count_interactive_templates(%{filter: attrs})

      interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))
      interactives = InteractiveTemplates.list_interactives(%{filter: attrs})

      assert length(interactives) == interactive_count + 2

      assert interactive1 in interactives
      assert interactive2 in interactives
    end

    test "list_interactives/1 with multiple items sorted",
         %{organization_id: _organization_id} = attrs do
      interactive_count = InteractiveTemplates.count_interactive_templates(%{filter: attrs})

      Fixtures.interactive_fixture(attrs)
      Fixtures.interactive_fixture(Map.merge(attrs, @valid_more_attrs))

      interactives =
        InteractiveTemplates.list_interactives(%{opts: %{order: :asc}, filter: attrs})

      assert length(interactives) == interactive_count + 2
    end

    test "list_interactives/1 with items filtered",
         %{organization_id: _organization_id} = attrs do
      _interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))

      interactives =
        InteractiveTemplates.list_interactives(%{
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
        InteractiveTemplates.list_interactives(%{
          opts: %{order: :asc},
          filter: Map.merge(%{type: :quick_reply}, attrs)
        })

      assert length(interactives) == 3
      assert interactive1 in interactives
      assert interactive2 in interactives
    end
  end
end
