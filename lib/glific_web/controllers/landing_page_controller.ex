defmodule GlificWeb.LandingPageController do
  use GlificWeb, :controller

  def index(conn,_params) do
    render(conn,"landing_page.html", page_title: "Glific Backend")
  end
end
