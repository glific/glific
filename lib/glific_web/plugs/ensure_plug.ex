if Code.ensure_loaded?(Plug) do
  defmodule GlificWeb.EnsurePlug do
    @moduledoc """
    This is a basic plug that ensure the organization is loaded.

    To plug it on your router, you can use:

        plug GlificWeb.EnsurePlug,
          callback: &OrganizationHelper.callback/2
          failure_callback: &OrganizationHelper.failure_callback/2

    See `GlificWeb.EnsurePlugConfig` to check all the allowed `config` flags.
    """

    alias __MODULE__
    alias GlificWeb.Plug

    @doc false
    def init(opts), do: struct(EnsurePlugConfig, opts)

    @doc false
    def call(conn, config), do: Plug.ensure_organization(conn, config)
  end
end
