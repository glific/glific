defmodule Glific.AI.ToolsTest do
  use Glific.DataCase

  alias Glific.{AI.Tools, Fixtures, Flows.Flow, Repo}

  defmodule WritingTool do
    @moduledoc false
    @behaviour Glific.AI.Tool

    @impl Glific.AI.Tool
    def name, do: "writing_tool"
    @impl Glific.AI.Tool
    def description, do: "attempts a write, to prove it cannot"
    @impl Glific.AI.Tool
    def parameters, do: []

    @impl Glific.AI.Tool
    def run(_args) do
      Glific.Flows.Flow
      |> Glific.Repo.all()
      |> hd()
      |> Ecto.Changeset.change(%{name: "written by a tool"})
      |> Glific.Repo.update()

      {:ok, :wrote}
    end
  end

  defmodule RaisingTool do
    @moduledoc false
    @behaviour Glific.AI.Tool

    @impl Glific.AI.Tool
    def name, do: "raising_tool"
    @impl Glific.AI.Tool
    def description, do: "raises, to prove the gateway catches it"
    @impl Glific.AI.Tool
    def parameters, do: []
    @impl Glific.AI.Tool
    def run(_args), do: raise("something went wrong deep inside")
  end

  setup do
    original = Application.get_env(:glific, Tools, [])
    Application.put_env(:glific, Tools, tools: Tools.all() ++ [WritingTool, RaisingTool])
    on_exit(fn -> Application.put_env(:glific, Tools, original) end)

    user = Fixtures.user_fixture(%{organization_id: 1})
    flow = Fixtures.flow_fixture(%{organization_id: 1, name: "Registration flow"})
    %{user: user, flow: flow}
  end

  describe "the gateway's guarantees" do
    test "an unknown tool is reported, not raised", %{user: user} do
      assert {:error, message} = Tools.run("no_such_tool", %{}, user)
      assert message =~ "no tool called"
    end

    test "invalid arguments are reported, not raised", %{user: user} do
      assert {:error, message} = Tools.run("get_flow", %{"flow_id" => "not a number"}, user)
      assert is_binary(message)
      assert {:error, _} = Tools.run("get_flow", %{}, user)
    end

    test "an argument name that is not a known atom does not crash", %{user: user} do
      assert {:ok, _} = Tools.run("list_flows", %{"definitely_not_an_argument_name" => 1}, user)
    end

    test "an exception inside a tool comes back as a result", %{user: user} do
      assert {:error, message} = Tools.run("raising_tool", %{}, user)
      assert message =~ "something went wrong deep inside"
    end

    test "the read runs as the given user, whatever the process state said", %{user: user} do
      Repo.put_current_user(Fixtures.user_fixture(%{organization_id: 1, phone: "919876500011"}))

      assert {:ok, _} = Tools.run("list_flows", %{}, user)
      assert Repo.get_current_user().id == user.id
    end

    test "a tool cannot see another organisation's data", %{user: user} do
      other_org = Fixtures.organization_fixture(%{shortcode: "ai_tools_other"})
      other_user = Fixtures.user_fixture(%{organization_id: other_org.id, phone: "919876500012"})

      assert {:ok, mine} = Tools.run("list_flows", %{}, user)
      assert Enum.any?(mine, &(&1.name == "Registration flow"))

      assert {:ok, theirs} = Tools.run("list_flows", %{}, other_user)
      refute Enum.any?(theirs, &(&1.name == "Registration flow"))
    end
  end

  describe "the tools themselves" do
    test "list_flows finds a flow by partial name", %{user: user} do
      assert {:ok, flows} = Tools.run("list_flows", %{"name" => "Registration"}, user)
      assert [%{name: "Registration flow"} | _] = flows
    end

    test "get_flow explains an unknown id rather than failing", %{user: user} do
      assert {:error, message} = Tools.run("get_flow", %{"flow_id" => 999_999}, user)
      assert message =~ "No flow with id 999999"
    end

    test "flow_status reports where contacts are", %{user: user, flow: flow} do
      assert {:ok, result} = Tools.run("flow_status", %{"flow_id" => flow.id}, user)
      assert result.flow.name == "Registration flow"
      assert %{waiting_at_node: _, completed: _, stopped: _} = result.contacts
    end

    test "list_contact_fields and list_templates return data", %{user: user} do
      Fixtures.contacts_field_fixture(%{organization_id: 1, name: "Age", shortcode: "age"})

      assert {:ok, fields} = Tools.run("list_contact_fields", %{}, user)
      assert Enum.any?(fields, &(&1.shortcode == "age"))

      assert {:ok, templates} = Tools.run("list_templates", %{"limit" => 5}, user)
      assert is_list(templates)
    end
  end

  test "every registered tool declares a name, a description and a schema" do
    for tool <- Tools.all(), tool not in [WritingTool, RaisingTool] do
      assert is_binary(tool.name()) and tool.name() != ""
      assert is_binary(tool.description()) and tool.description() != ""
      assert is_list(tool.parameters())
      assert {:ok, tool} == Tools.fetch(tool.name())
    end
  end

  test "a write inside a tool is refused by the database", %{user: user} do
    original = Flow |> Repo.all() |> hd()

    assert {:error, message} = Tools.run("writing_tool", %{}, user)

    assert message =~ "read-only" or message =~ "cannot execute"
    assert Repo.get(Flow, original.id).name == original.name
  end
end
