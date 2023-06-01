defmodule GlificWeb.LandingPageControllerTest do
  use GlificWeb.ConnCase

  test "GET / renders the landing page", %{conn:conn} do
    conn = get(conn,"/")
    assert html_response(conn,200) =- "Welcome to Glific Backend!"
  end
end
