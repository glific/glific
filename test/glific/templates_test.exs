defmodule Glific.TemplatesTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Settings,
    Templates,
    Templates.SessionTemplate
  }

  describe "session_template" do
    @valid_attrs %{
      label: "some label",
      body: "some body",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @valid_attrs_1 %{
      label: "Another label",
      body: "some body 1",
      shortcode: "sl1",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @valid_attrs_to_test_order_1 %{
      label: "aaaa label",
      body: "some body 2",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @valid_attrs_to_test_order_2 %{
      label: "zzzz label",
      body: "some body 2",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @update_attrs %{
      label: "some updated label",
      body: "some updated body"
    }

    @invalid_attrs %{
      label: nil,
      body: nil,
      language_id: nil
    }

    @valid_language_attrs %{
      label: "English (United States)",
      label_locale: "English",
      locale: "en_US",
      is_active: true
    }
    @valid_language_attrs_1 %{
      label: "Hindi (United States)",
      label_locale: "हिन्दी",
      locale: "hi_US",
      is_active: true
    }

    def language_fixture(attrs \\ %{}) do
      {:ok, language} =
        attrs
        |> Enum.into(@valid_language_attrs)
        |> Settings.language_upsert()

      language
    end

    def session_template_fixture(attrs) do
      language = language_fixture()

      {:ok, session_template} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Templates.create_session_template()

      session_template
    end

    test "list_session_templates/1 returns all session_templates", attrs do
      templates_count = Templates.count_session_templates(%{filter: attrs})

      _session_template = session_template_fixture(attrs)
      assert length(Templates.list_session_templates(%{filter: attrs})) == templates_count + 1
    end

    test "count_session_templates/0 returns count of all session templates", attrs do
      templates_count = Templates.count_session_templates(%{filter: attrs})

      session_template_fixture(attrs)
      assert Templates.count_session_templates(%{filter: attrs}) == templates_count + 1

      session_template_fixture(Map.merge(attrs, @valid_attrs_1))
      assert Templates.count_session_templates(%{filter: attrs}) == templates_count + 2

      assert Templates.count_session_templates(%{
               filter: Map.merge(attrs, %{label: "Another label"})
             }) == 1
    end

    test "list_session_templates/1 with multiple session_templates filteres", attrs do
      _session_template = session_template_fixture(attrs)
      session_template1 = session_template_fixture(Map.merge(attrs, @valid_attrs_1))

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{label: session_template1.label})
        })

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{body: session_template1.body})
        })

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{shortcode: session_template1.shortcode})
        })

      assert session_template_list == [session_template1]
    end

    test "list_session_templates/1 with term filter on session_templates", attrs do
      # Match term with labe/body/shortcode of template
      session_template_fixture(Map.merge(attrs, %{label: "filterterm"}))
      session_template_fixture(Map.merge(attrs, %{label: "label2", body: "filterterm"}))
      session_template_fixture(Map.merge(attrs, %{label: "label3", shortcode: "filterterm"}))

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 3

      # Match term with label/shortcode of associated tag
      template = session_template_fixture(Map.merge(attrs, %{label: "label4"}))
      tag_1 = Fixtures.tag_fixture(Map.merge(attrs, %{label: "filterterm"}))

      _template_tag =
        Fixtures.template_tag_fixture(
          Map.merge(attrs, %{template_id: template.id, tag_id: tag_1.id})
        )

      template = session_template_fixture(Map.merge(attrs, %{label: "label5"}))
      tag_2 = Fixtures.tag_fixture(Map.merge(attrs, %{shortcode: "filterterm"}))

      _template_tag =
        Fixtures.template_tag_fixture(
          Map.merge(attrs, %{template_id: template.id, tag_id: tag_2.id})
        )

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 5

      # In case of a template tagged with multiple tags with similar label or shortcode
      # result should not give repeated templates
      _template_tag =
        Fixtures.template_tag_fixture(
          Map.merge(attrs, %{template_id: template.id, tag_id: tag_1.id})
        )

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 5
    end

    test "list_session_templates/1 with multiple items", attrs do
      templates_count = Templates.count_session_templates(%{filter: attrs})

      session_template_fixture(attrs)
      session_template_fixture(Map.merge(attrs, @valid_attrs_1))

      session_templates = Templates.list_session_templates(%{filter: attrs})
      assert length(session_templates) == templates_count + 2
    end

    test "list_session_templates/1 with multiple items sorted", attrs do
      session_templates_count = Templates.count_session_templates(%{filter: attrs})

      s0 = session_template_fixture(Map.merge(attrs, @valid_attrs_to_test_order_1))
      s1 = session_template_fixture(Map.merge(attrs, @valid_attrs_to_test_order_2))

      assert length(Templates.list_session_templates(%{filter: attrs})) ==
               session_templates_count + 2

      [ordered_s0 | _] = Templates.list_session_templates(%{opts: %{order: :asc}, filter: attrs})
      assert s0 == ordered_s0

      [ordered_s1 | _] = Templates.list_session_templates(%{opts: %{order: :desc}, filter: attrs})
      assert s1 == ordered_s1
    end

    test "get_session_template!/1 returns the session_template with given id", attrs do
      session_template = session_template_fixture(attrs)
      assert Templates.get_session_template!(session_template.id) == session_template
    end

    test "create_session_template/1 with valid data creates a message", attrs do
      language = language_fixture()

      attrs =
        attrs
        |> Map.merge(@valid_attrs)
        |> Map.merge(%{language_id: language.id})

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.label == "some label"
      assert session_template.body == "some body"
      assert session_template.shortcode == nil
      assert session_template.is_active == true
      assert session_template.is_reserved == true
      assert session_template.is_source == false
      assert session_template.language_id == language.id
    end

    test "create_session_template/1 with invalid data returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} =
               Templates.create_session_template(Map.merge(attrs, @invalid_attrs))
    end

    test "update_session_template/2 with valid data updates the session_template", attrs do
      session_template = session_template_fixture(attrs)
      language = language_fixture(@valid_language_attrs_1)
      attrs = Map.merge(@update_attrs, %{language_id: language.id})

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.update_session_template(session_template, attrs)

      assert session_template.label == @update_attrs.label
      assert session_template.body == @update_attrs.body
      assert session_template.language_id == language.id
    end

    test "update_session_template/2 with invalid data returns error changeset", attrs do
      session_template = session_template_fixture(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Templates.update_session_template(session_template, @invalid_attrs)

      assert session_template == Templates.get_session_template!(session_template.id)
    end

    test "delete_session_template/1 deletes the session_template", attrs do
      session_template = session_template_fixture(attrs)
      assert {:ok, %SessionTemplate{}} = Templates.delete_session_template(session_template)

      assert_raise Ecto.NoResultsError, fn ->
        Templates.get_session_template!(session_template.id)
      end
    end

    test "change_session_template/1 returns a session_template changeset", attrs do
      session_template = session_template_fixture(attrs)
      assert %Ecto.Changeset{} = Templates.change_session_template(session_template)
    end

    test "ensure that creating session template with out language and/or org_id give an error" do
      assert {:error, %Ecto.Changeset{}} = Templates.create_session_template(@valid_attrs)
    end
  end
end
