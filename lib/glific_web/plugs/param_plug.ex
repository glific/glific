if Code.ensure_loaded?(Plug) do
  defmodule GlificWeb.ParamPlug do
    @moduledoc """
    This is a basic plug that loads the current organization assign from a given
    param.

    To plug it on your router, you can use:

        plug GlificWeb.ParamPlug,
          param: :subdomain,
          organization_handler: &OrganizationHelper.organization_handler/1

    See `GlificWeb.ParamPlugConfig` to check all the allowed `config` flags.
    """

    alias Plug.Conn
    alias GlificWeb.ParamPlugConfig
    alias GlificWeb.Plug


    @doc false
    @spec init(any) :: %{:__struct__ => atom, optional(atom) => any}
    def init(opts), do: struct(ParamPlugConfig, opts)

    @doc false
    @spec call(Conn.t(), map()) :: Conn.t()
    def call(conn, config), do: Plug.put_organization(conn, get_param(conn, config), config)

    @spec get_param(any(), map()) :: any()
    defp get_param(conn, %ParamPlugConfig{param: key}),
      do: get_param(conn, key)

    defp get_param(conn, key) when is_atom(key),
      do: get_param(conn, Atom.to_string(key))

    defp get_param(conn, key),
      do: conn.params[key]
  end
end
