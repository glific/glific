defmodule Glific.TemplatesTest do
  use Glific.DataCase

  alias Glific.{
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

    def session_template_fixture(attrs \\ %{}) do
      language = language_fixture()

      {:ok, session_template} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Templates.create_session_template()

      session_template
    end

    test "list_session_templates/0 returns all session_templates" do
      templates_count = Repo.aggregate(SessionTemplate, :count)

      _session_template = session_template_fixture()
      assert length(Templates.list_session_templates()) == templates_count + 1
    end

    test "count_session_templates/0 returns count of all session templates" do
      templates_count = Repo.aggregate(SessionTemplate, :count)

      session_template_fixture()
      assert Templates.count_session_templates() == templates_count + 1

      session_template_fixture(@valid_attrs_1)
      assert Templates.count_session_templates() == templates_count + 2

      assert Templates.count_session_templates(%{filter: %{label: "Another label"}}) == 1
    end

    test "list_session_templates/1 with multiple session_templates filteres" do
      _session_template = session_template_fixture()
      session_template1 = session_template_fixture(@valid_attrs_1)

      session_template_list =
        Templates.list_session_templates(%{filter: %{label: session_template1.label}})

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{filter: %{body: session_template1.body}})

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{filter: %{shortcode: session_template1.shortcode}})

      assert session_template_list == [session_template1]

      session_template_fixture(%{label: "term_filter"})
      session_template_fixture(%{label: "label2", body: "term_filter"})
      session_template_fixture(%{label: "label3", shortcode: "term_filter"})

      session_template_list = Templates.list_session_templates(%{filter: %{term: "term_filter"}})

      assert length(session_template_list) == 3
    end

    test "list_session_templates/1 with multiple items" do
      templates_count = Repo.aggregate(SessionTemplate, :count)

      session_template_fixture()
      session_template_fixture(@valid_attrs_1)

      session_templates = Templates.list_session_templates()
      assert length(session_templates) == templates_count + 2
    end

    test "list_session_templates/1 with multiple items sorted" do
      session_templates_count = Repo.aggregate(SessionTemplate, :count)

      s0 = session_template_fixture(@valid_attrs_to_test_order_1)
      s1 = session_template_fixture(@valid_attrs_to_test_order_2)

      assert length(Templates.list_session_templates()) == session_templates_count + 2

      [ordered_s0 | _] = Templates.list_session_templates(%{opts: %{order: :asc}})
      assert s0 == ordered_s0

      [ordered_s1 | _] = Templates.list_session_templates(%{opts: %{order: :desc}})
      assert s1 == ordered_s1
    end

    test "get_session_template!/1 returns the session_template with given id" do
      session_template = session_template_fixture()
      assert Templates.get_session_template!(session_template.id) == session_template
    end

    test "create_session_template/1 with valid data creates a message" do
      language = language_fixture()
      attrs = Map.merge(@valid_attrs, %{language_id: language.id})

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

    test "create_session_template/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Templates.create_session_template(@invalid_attrs)
    end

    test "create session template with media type and without media id returns error changeset" do
      language = language_fixture()
      attrs = Map.merge(@valid_attrs, %{language_id: language.id})

      assert {:error, %Ecto.Changeset{}} =
               attrs
               |> Map.merge(%{type: :image})
               |> Templates.create_session_template()
    end

    test "update_session_template/2 with valid data updates the session_template" do
      session_template = session_template_fixture()
      language = language_fixture(@valid_language_attrs_1)
      attrs = Map.merge(@update_attrs, %{language_id: language.id})

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.update_session_template(session_template, attrs)

      assert session_template.label == @update_attrs.label
      assert session_template.body == @update_attrs.body
      assert session_template.language_id == language.id
    end

    test "update_session_template/2 with invalid data returns error changeset" do
      session_template = session_template_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Templates.update_session_template(session_template, @invalid_attrs)

      assert session_template == Templates.get_session_template!(session_template.id)
    end

    test "delete_session_template/1 deletes the session_template" do
      session_template = session_template_fixture()
      assert {:ok, %SessionTemplate{}} = Templates.delete_session_template(session_template)

      assert_raise Ecto.NoResultsError, fn ->
        Templates.get_session_template!(session_template.id)
      end
    end

    test "change_session_template/1 returns a session_template changeset" do
      session_template = session_template_fixture()
      assert %Ecto.Changeset{} = Templates.change_session_template(session_template)
    end

    test "ensure that creating session template with out language give an error" do
      assert {:error, %Ecto.Changeset{}} = Templates.create_session_template(@valid_attrs)
    end
  end
end
