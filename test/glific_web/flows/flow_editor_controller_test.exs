defmodule GlificWeb.Flows.FlowEditorControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Flows,
    Flows.FlowLabel,
    Groups,
    Settings,
    Templates
  }

  alias GlificWeb.Flows.FlowEditorController

  @valid_language_attrs %{
    label: "English",
    label_locale: "English",
    locale: "en",
    is_active: true
  }

  @valid_attrs %{
    label: "some label",
    body: "some body",
    type: :text,
    is_active: true,
    is_reserved: true,
    status: "APPROVED"
  }

  describe "flow_editor_routes" do
    test "globals", %{conn: conn} do
      conn = get(conn, "/flow-editor/globals", %{})
      assert json_response(conn, 200) == %{"results" => []}
    end

    test "groups", %{conn: conn} do
      groups = Groups.list_groups(%{filter: %{organization_id: conn.assigns[:organization_id]}})
      conn = get(conn, "/flow-editor/groups", %{})
      assert length(json_response(conn, 200)["results"]) == length(groups)
    end

    test "groups_post", %{conn: conn} do
      conn = post(conn, "/flow-editor/groups", %{"name" => "test group"})

      assert json_response(conn, 200)["name"] ==
               "ALERT: PLEASE CREATE NEW GROUP FROM THE ORGANIZATION SETTINGS"
    end

    test "fields", %{conn: conn} do
      conn = get(conn, "/flow-editor/fields", %{})
      assert length(json_response(conn, 200)["results"]) > 0
    end

    test "fields_post", %{conn: conn} do
      conn = post(conn, "/flow-editor/fields", %{"label" => "Some Field name"})

      assert json_response(conn, 200) == %{
               "key" => "some_field_name",
               "name" => "Some Field name",
               "label" => "Some Field name",
               "value_type" => "text"
             }
    end

    test "labels", %{conn: conn} do
      flows = FlowLabel.get_all_flowlabel(conn.assigns[:organization_id])
      conn = get(conn, "/flow-editor/labels", %{})
      assert length(json_response(conn, 200)["results"]) == length(flows)
    end

    test "labels_post", %{conn: conn} do
      conn = post(conn, "/flow-editor/labels", %{"name" => "Test Lable"})
      results = json_response(conn, 200)
      assert results["name"] == "Test Lable"
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

      assert length(
               Glific.Templates.list_session_templates(%{
                 filter: %{organization_id: conn.assigns[:organization_id]}
               })
             ) ==
               length(templates)
    end

    def language_fixture(attrs \\ %{}) do
      {:ok, language} =
        attrs
        |> Enum.into(@valid_language_attrs)
        |> Settings.language_upsert()

      language
    end

    test "languages", %{conn: conn} do
      conn = get(conn, "/flow-editor/languages", %{})
      languages = json_response(conn, 200)["results"]

      assert length(Glific.Partners.organization(conn.assigns[:organization_id]).languages) ==
               length(languages)
    end

    test "environment", %{conn: conn} do
      conn = get(conn, "/flow-editor/environment", %{})
      assert json_response(conn, 200) == %{}
    end

    test "recipients", %{conn: conn} do
      conn = get(conn, "/flow-editor/recipients", %{})
      # we have already create quite a few users and contacts, so this will
      # have a gew recipients
      assert json_response(conn, 200)["results"] != []
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

    test "listing templates in Flow should return the list of approved templates",
         %{conn: conn} = attrs do
      language = language_fixture()

      attrs =
        attrs
        |> Map.merge(@valid_attrs)
        |> Map.merge(%{language_id: language.id})

      Templates.create_session_template(attrs)

      {:ok, results} = FlowEditorController.templates(conn, %{}).resp_body |> Jason.decode()

      approved_templates =
        Templates.list_session_templates(%{
          filter: %{organization_id: conn.assigns[:organization_id], status: "APPROVED"}
        })

      assert length(results["results"]) == length(approved_templates)
    end

    test "get all the flows", %{conn: conn} do
      flows = Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})
      conn = get(conn, "/flow-editor/flows", %{})
      results = json_response(conn, 200)["results"]
      assert length(flows) == length(results)
    end

    test "Flow with UUID should return the latest difination", %{conn: conn} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      conn = get(conn, "/flow-editor/flows/#{flow.uuid}", %{})
      results = json_response(conn, 200)["results"]
      assert results == Flows.Flow.get_latest_definition(flow.id)
    end

    test "Get a list of all flow revisions", %{conn: conn} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      conn = get(conn, "/flow-editor/revisions/#{flow.uuid}", %{})
      results = json_response(conn, 200)["results"]
      assert length(Flows.get_flow_revision_list(flow.uuid)[:results]) == length(results)
    end

    test "Get a specific revision for a flow", %{conn: conn} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      [revision | _tail] = Flows.get_flow_revision_list(flow.uuid)[:results]

      conn = get(conn, "/flow-editor/revisions/#{flow.uuid}/#{revision.id}", %{})
      results = json_response(conn, 200)["definition"]
      assert Flows.get_flow_revision(flow.uuid, revision.id)[:definition] == results
    end

    test "Save a revision for a flow", %{conn: conn} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

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
