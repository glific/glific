defmodule GlificWeb.EnsurePlugConfig do
  @moduledoc """
  This is a struct that holds the configuration for `GlificWeb.EnsurePlug`.

  Here are the config keys allowed:

  - `assign`: the name of the assign where we must save the organization.
  - `callback`: function that might be called when the plug succeeded. It
  must return a connection.
  - `failure_callback`: function that might be called when the plug failed.
  It must return a connection.
  """

  defstruct [:callback, :failure_callback, assign: :current_organization]
end
