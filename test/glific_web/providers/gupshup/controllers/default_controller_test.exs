defmodule GlificWeb.Providers.Gupshup.Controllers.DefaultControllerTest do
  use GlificWeb.ConnCase

  describe "unknown" do
    test "unknown should return empty data", %{conn: conn} do
      conn = post(conn, "/gupshup")
      assert response(conn, 200) == ""
    end
  end
end
