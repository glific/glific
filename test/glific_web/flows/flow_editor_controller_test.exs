defmodule GlificWeb.Flows.FlowEditorControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Flows
  alias Glific.Groups
  alias Glific.Tags

  describe "flow_editor_routes" do
    test "globals", %{conn: conn} do
      conn = get(conn, "/flow-editor/globals", %{})
      assert json_response(conn, 200) == %{"results" => []}
    end

    test "groups", %{conn: conn} do
      groups = Groups.list_groups()
      conn = get(conn, "/flow-editor/groups", %{})
      assert length(json_response(conn, 200)["results"]) == length(groups)
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
      tags = Tags.list_tags(%{filter: %{parent: "Contacts"}})
      conn = get(conn, "/flow-editor/labels", %{})
      assert length(json_response(conn, 200)["results"]) == length(tags)
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
      assert length(Glific.Templates.list_session_templates()) == length(templates)
    end

    test "languages", %{conn: conn} do
      conn = get(conn, "/flow-editor/languages", %{})
      languages = json_response(conn, 200)["results"]
      assert length(Glific.Settings.list_languages()) == length(languages)
    end

    test "environment", %{conn: conn} do
      conn = get(conn, "/flow-editor/environment", %{})
      assert json_response(conn, 200) == %{}
    end

    test "recipients", %{conn: conn} do
      conn = get(conn, "/flow-editor/recipients", %{})
      assert json_response(conn, 200)["results"] == []
    end

    test "completion", %{conn: conn} do
      conn = get(conn, "/flow-editor/completion", %{})

      completion =
        File.read!(Path.join(:code.priv_dir(:glific), "data/flows/completion.json"))
        |> Jason.decode!()

      assert json_response(conn, 200) == completion
    end

    test "activity", %{conn: conn} do
      conn = get(conn, "/flow-editor/activity", %{})
      response = json_response(conn, 200)
      assert Map.has_key?(response, "nodes")
      assert Map.has_key?(response, "segments")
    end

    test "get all the flows", %{conn: conn} do
      flows = Flows.list_flows()
      conn = get(conn, "/flow-editor/flows", %{})
      results = json_response(conn, 200)["results"]
      assert length(flows) == length(results)
    end

    test "Flow with UUID should return the latest difination", %{conn: conn} do
      [flow | _tail] = Flows.list_flows()
      conn = get(conn, "/flow-editor/flows/#{flow.uuid}", %{})
      results = json_response(conn, 200)["results"]
      assert results == Flows.Flow.get_latest_definition(flow.id)
    end

    test "Get a list of all flow revisions", %{conn: conn} do
      [flow | _tail] = Flows.list_flows()
      conn = get(conn, "/flow-editor/revisions/#{flow.uuid}", %{})
      results = json_response(conn, 200)["results"]
      assert length(Flows.get_flow_revision_list(flow.uuid)[:results]) == length(results)
    end

    test "Get a specific revision for a flow", %{conn: conn} do
      [flow | _tail] = Flows.list_flows()
      [revision | _tail] = Flows.get_flow_revision_list(flow.uuid)[:results]

      conn = get(conn, "/flow-editor/revisions/#{flow.uuid}/#{revision.id}", %{})
      results = json_response(conn, 200)["definition"]
      assert Flows.get_flow_revision(flow.uuid, revision.id)[:definition] == results
    end

    test "Save a revision for a flow", %{conn: conn} do
      [flow | _tail] = Flows.list_flows()
      flow = Glific.Repo.preload(flow, :revisions)
      [revision | _tail] = flow.revisions

      conn = post(conn, "/flow-editor/revisions", revision.definition)
      revision_id = json_response(conn, 200)["revision"]

      assert Glific.Repo.get!(Flows.FlowRevision, revision_id) != nil
    end

    test "functions", %{conn: conn} do
      functions =
        File.read!(Path.join(:code.priv_dir(:glific), "data/flows/functions.json"))
        |> Jason.decode!()

      conn = get(conn, "/flow-editor/functions", %{})
      assert json_response(conn, 200) == functions
    end
  end
end
