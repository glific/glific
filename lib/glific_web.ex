defmodule GlificWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use GlificWeb, :controller
      use GlificWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def static_paths, do: ~w(assets flows fonts images favicon.ico robots.txt)

  def controller do
    quote do
      use Phoenix.Controller, namespace: GlificWeb

      import Plug.Conn
      use Gettext, backend: GlificWeb.Gettext
      alias GlificWeb.Router.Helpers, as: Routes
      unquote(verified_routes())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/glific_web/templates",
        namespace: GlificWeb

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      import Phoenix.LiveView.Helpers

      import Phoenix.Component

      # Include shared imports and aliases for views
      unquote(view_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {GlificWeb.LayoutView, :live}

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import Phoenix.Component
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      use Gettext, backend: GlificWeb.Gettext
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      # Import LiveView helpers (live_render, live_component, live_patch, etc)
      import Phoenix.LiveView.Helpers

      unquote(verified_routes())

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      import GlificWeb.ErrorHelpers
      use Gettext, backend: GlificWeb.Gettext
      alias GlificWeb.Router.Helpers, as: Routes
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: GlificWeb.Endpoint,
        router: GlificWeb.Router,
        statics: GlificWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
