defmodule GlificWeb.Flows.FlowEditorControllerTest do
  use GlificWeb.ConnCase

  setup do
    :ok
  end

  describe "flow_editor_routes" do
    test "globals", %{conn: conn} do
      conn = get(conn, "/flow-editor/globals", %{})
      assert json_response(conn, 200) == %{"results" => []}
    end

    test "groups", %{conn: conn} do
      conn = get(conn, "/flow-editor/groups", %{})
      assert json_response(conn, 200) == %{"results" => []}
    end

    test "groups_post", %{conn: conn} do
      conn = post(conn, "/flow-editor/groups", %{"name" => "test group"})
      assert json_response(conn, 200)["name"] == "test group"
    end

    test "fields", %{conn: conn} do
      fileds = [
        %{"key" => "name", "name" => "Name", "value_type" => "text"},
        %{"key" => "age_group", "name" => "Age Group", "value_type" => "text"},
        %{"key" => "gender", "name" => "Gender", "value_type" => "text"},
        %{"key" => "dob", "name" => "Date of Birth", "value_type" => "text"},
        %{"key" => "settings", "name" => "Settings", "value_type" => "text"}
      ]

      conn = get(conn, "/flow-editor/fields", %{})
      assert json_response(conn, 200)["results"] == fileds
    end

    test "fields_post", %{conn: conn} do
      conn = post(conn, "/flow-editor/fields", %{"label" => "Some Field name"})
      assert json_response(conn, 200) == %{}
    end

    test "labels", %{conn: conn} do
      conn = get(conn, "/flow-editor/labels", %{})
      assert json_response(conn, 200)["results"] == []
    end

    test "labels_post", %{conn: conn} do
      conn = post(conn, "/flow-editor/labels", %{"name" => "Test Lable"})
      assert json_response(conn, 200) == %{}
    end

    test "channels", %{conn: conn} do
      conn = get(conn, "/flow-editor/channels", %{})
      data = json_response(conn, 200)
      assert [map] = data["results"]
      assert map["name"] == "WhatsApp"
    end

    test "classifiers", %{conn: conn} do
      conn = get(conn, "/flow-editor/classifiers", %{})
      assert json_response(conn, 200)["results"] == []
    end

    test "ticketers", %{conn: conn} do
      conn = get(conn, "/flow-editor/ticketers", %{})
      assert json_response(conn, 200)["results"] == []
    end

    test "resthooks", %{conn: conn} do
      conn = get(conn, "/flow-editor/resthooks", %{})
      assert json_response(conn, 200)["results"] == []
    end

    test "templates", %{conn: conn} do
      conn = get(conn, "/flow-editor/templates", %{})
      templates = json_response(conn, 200)["results"]
      assert Glific.Templates.list_session_templates() == templates
    end

    # test "languages", %{conn: conn} do
    #   conn = get(conn, "/flow-editor/classifiers", %{})
    #   assert json_response(conn, 200)["results"] == []
    # end

    # test "environment", %{conn: conn} do
    #   conn = get(conn, "/flow-editor/classifiers", %{})
    #   assert json_response(conn, 200)["results"] == []
    # end

    # test "recipients", %{conn: conn} do
    #   conn = get(conn, "/flow-editor/classifiers", %{})
    #   assert json_response(conn, 200)["results"] == []
    # end

    # test "completion", %{conn: conn} do
    #   conn = get(conn, "/flow-editor/classifiers", %{})
    #   assert json_response(conn, 200)["results"] == []
    # end

    # test "completion", %{conn: conn} do
    #   conn = get(conn, "/flow-editor/classifiers", %{})
    #   assert json_response(conn, 200)["results"] == []
    # end
  end
end
