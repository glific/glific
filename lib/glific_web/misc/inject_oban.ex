defmodule GlificWeb.InjectOban do
  @moduledoc """
  Simple macro to conditionally load Oban.Web only if already loaded. This allows
  us to include it only in the production release and hence make it a lot easier on potential
  open source contributors. We thus avoid the problem of sharing the oban key and/or them hacking
  the code to get it working

  Thanx to @manu from DataOGram and @benwilson from Absinthe/GraphQL for help with this feature.
  """

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
