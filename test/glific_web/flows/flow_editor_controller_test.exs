defmodule GlificWeb.Flows.FlowEditorControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Fixtures,
    Flows,
    Flows.FlowLabel,
    Groups,
    Settings,
    Templates
  }

  alias GlificWeb.Flows.FlowEditorController

  @password "secret1234"
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

  defp get_auth_token(conn, token) do
    conn
    |> Plug.Conn.put_req_header("authorization", token)
  end

  defp get_params do
    user = Fixtures.user_fixture()

    %{
      "user" => %{
        "phone" => user.phone,
        "name" => user.name,
        "password" => @password
      }
    }
  end

  defp get_token(valid_params, organization_id, conn) do
    params = put_in(valid_params, ["user", "organization_id"], organization_id)
    authed_conn = post(conn, Routes.api_v1_session_path(conn, :create, params))
    {:ok, access_token: authed_conn.private[:api_access_token]}
  end

  describe "flow_editor_routes" do
    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "globals", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/globals", %{})

      assert json_response(conn, 200) == %{"results" => []}
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "groups", %{conn: conn, access_token: token} do
      groups = Groups.list_groups(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/groups", %{})

      assert length(json_response(conn, 200)["results"]) == length(groups)
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "groups_post", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> post("/flow-editor/groups", %{"name" => "test group"})

      assert json_response(conn, 200)["name"] ==
               "ALERT: PLEASE CREATE NEW GROUP FROM THE ORGANIZATION SETTINGS"
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "fields", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/fields", %{})

      assert length(json_response(conn, 200)["results"]) > 0
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "fields_post", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> post("/flow-editor/fields", %{"label" => "Some Field name"})

      assert json_response(conn, 200) == %{
               "key" => "some_field_name",
               "name" => "Some Field name",
               "label" => "Some Field name",
               "value_type" => "text"
             }
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "labels", %{conn: conn, access_token: token} do
      flows = FlowLabel.get_all_flowlabel(conn.assigns[:organization_id])

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/labels", %{})

      assert length(json_response(conn, 200)["results"]) == length(flows)
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "labels_post", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> post("/flow-editor/labels", %{"name" => "Test Lable"})

      results = json_response(conn, 200)
      assert results["name"] == "Test Lable"
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "channels", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/channels", %{})

      data = json_response(conn, 200)
      assert [map] = data["results"]
      assert map["name"] == "WhatsApp"
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "classifiers", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/classifiers", %{})

      assert json_response(conn, 200)["results"] == []
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "ticketers", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/ticketers", %{})

      assert json_response(conn, 200)["results"] == []
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "resthooks", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/resthooks", %{})

      assert json_response(conn, 200)["results"] == []
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "templates", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/templates", %{})

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

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "languages", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/languages", %{})

      languages = json_response(conn, 200)["results"]

      assert length(Glific.Partners.organization(conn.assigns[:organization_id]).languages) ==
               length(languages)
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "environment", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/environment", %{})

      assert json_response(conn, 200) == %{}
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "recipients", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/recipients", %{})

      # we have already create quite a few users and contacts, so this will
      # have a gew recipients
      assert json_response(conn, 200)["results"] != []
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "completion", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/completion", %{})

      completion =
        File.read!(Path.join(:code.priv_dir(:glific), "data/flows/completion.json"))
        |> Jason.decode!()

      assert json_response(conn, 200) == completion
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "activity", %{conn: conn, access_token: token} do
      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/activity", %{})

      response = json_response(conn, 200)
      assert Map.has_key?(response, "nodes")
      assert Map.has_key?(response, "segments")
    end

    test "listing templates in Flow should return the list of approved templates",
         %{conn: conn, access_token: _token} = attrs do
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

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "get all the flows", %{conn: conn, access_token: token} do
      flows = Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/flows", %{})

      results = json_response(conn, 200)["results"]
      assert length(flows) == length(results)
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "Flow with UUID should return the latest difination", %{conn: conn, access_token: token} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/flows/#{flow.uuid}", %{})

      results = json_response(conn, 200)["results"]
      assert results == Flows.Flow.get_latest_definition(flow.id)
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "Get a list of all flow revisions", %{conn: conn, access_token: token} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/revisions/#{flow.uuid}", %{})

      results = json_response(conn, 200)["results"]
      assert length(Flows.get_flow_revision_list(flow.uuid)[:results]) == length(results)
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "Get a specific revision for a flow", %{conn: conn, access_token: token} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      [revision | _tail] = Flows.get_flow_revision_list(flow.uuid)[:results]

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/revisions/#{flow.uuid}/#{revision.id}", %{})

      results = json_response(conn, 200)["definition"]
      assert Flows.get_flow_revision(flow.uuid, revision.id)[:definition] == results
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "Save a revision for a flow", %{conn: conn, access_token: token} do
      [flow | _tail] =
        Flows.list_flows(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      flow = Glific.Repo.preload(flow, :revisions)
      [revision | _tail] = flow.revisions

      conn =
        get_auth_token(conn, token)
        |> post("/flow-editor/revisions", revision.definition)

      revision_id = json_response(conn, 200)["revision"]

      assert Glific.Repo.get!(Flows.FlowRevision, revision_id) != nil
    end

    setup %{conn: conn, organization_id: organization_id} do
      valid_params = get_params()
      get_token(valid_params, organization_id, conn)
    end

    test "functions", %{conn: conn, access_token: token} do
      functions =
        File.read!(Path.join(:code.priv_dir(:glific), "data/flows/functions.json"))
        |> Jason.decode!()

      conn =
        get_auth_token(conn, token)
        |> get("/flow-editor/functions", %{})

      assert json_response(conn, 200) == functions
    end
  end
end
