if Code.ensure_loaded?(Plug) do
  defmodule GlificWeb.EnsurePlug do
    alias Plug.Conn

    @moduledoc """
    This is a basic plug that ensure the organization is loaded.

    To plug it on your router, you can use:

        plug GlificWeb.EnsurePlug,
          callback: &OrganizationHelper.callback/2
          failure_callback: &OrganizationHelper.failure_callback/2

    See `GlificWeb.EnsurePlugConfig` to check all the allowed `config` flags.
    """

    alias GlificWeb.EnsurePlugConfig
    alias GlificWeb.Plug

    @doc false
    @spec init(any) :: %{:__struct__ => atom, optional(atom) => any}
    def init(opts), do: struct(EnsurePlugConfig, opts)

    @doc false
    @spec call(Conn.t(), map()) :: Conn.t()
    def call(conn, config), do: Plug.ensure_organization(conn, config)
  end
end
