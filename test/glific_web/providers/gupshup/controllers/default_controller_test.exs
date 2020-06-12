defmodule GlificWeb.DefaultControllerTest do
  use GlificWeb.ConnCase

  describe "unknown" do
    test "unknown should return empty data", %{conn: conn} do
      conn = post(conn, "/gupshup")
      assert json_response(conn, 200) == nil
    end
  end
end
