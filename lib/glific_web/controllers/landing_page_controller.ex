defmodule GlificWeb.LandingPageController do
  @moduledoc false
  use GlificWeb, :controller

  @doc false
  def index(conn,_params) do
    render(conn,"landing_page.html", page_title: "Glific Backend")
  end
end
