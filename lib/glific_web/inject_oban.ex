defmodule GlificWeb.InjectOban do
  @moduledoc false

  defmacro __using__(_) do
    if Code.ensure_loaded?(Oban.Web.Router) do
      quote do
        import Oban.Web.Router

        scope "/" do
          pipe_through [:browser, :auth]

          oban_dashboard("/oban")
        end
      end
    end
  end
end
