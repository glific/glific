if Code.ensure_loaded?(Plug) do
  defmodule GlificWeb.SubdomainPlug do
    @moduledoc """
    This is a basic plug that loads the current organization assign from a given
    value set on subdomain.

    To plug it on your router, you can use:

        plug GlificWeb.SubdomainPlug,
          endpoint: MyApp.Endpoint,
          organization_handler: &OrganizationHelper.organization_handler/1

    See `GlificWeb.SubdomainPlugConfig` to check all the allowed `config` flags.
    """

    alias Plug.Conn

    alias GlificWeb.Plug
    alias GlificWeb.SubdomainPlugConfig

    @doc false
    @spec init(any) :: %{:__struct__ => atom, optional(atom) => any}
    def init(opts), do: struct(SubdomainPlugConfig, opts)

    @doc false
    @spec call(Conn.t(), map()) :: Conn.t()
    def call(conn, config) do
      Plug.put_organization(conn, get_subdomain(conn, config), config)
    end

    @spec get_subdomain(Conn.t(), map()) :: String.t()
    defp get_subdomain(_conn, %SubdomainPlugConfig{endpoint: nil}) do
      nil
    end

    defp get_subdomain(
           %Conn{host: host},
           %SubdomainPlugConfig{endpoint: endpoint}
    ) do
      root_host = endpoint.config(:url)[:host]

      cond do
        host in ["0.0.0.0", "www.example.com"] -> nil

        # this is just a temporary fix for now to get CI up and running
        # we need a better long term solution soon
        host in ["localhost", root_host, "127.0.0.1"] -> "glific"

        true ->
          host
          |> String.replace(~r/.?#{root_host}/, "")
          |> String.replace("api.", "")
      end
    end
  end
end
