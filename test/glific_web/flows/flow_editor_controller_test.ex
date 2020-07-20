defmodule GlificWeb.Flows.FlowEditorControllerTest do
  use GlificWeb.ConnCase

  setup do
    :ok
  end

  describe "globals" do
    test "globals", %{conn: conn} do
      conn = get(conn, "/flow-editor/globals", %{})
      assert json_response(conn, 200) == nil
    end
  end
end
