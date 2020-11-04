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
      organization_id = get_subdomain(conn, config)
      Glific.Repo.put_organization_id(organization_id)
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

      if host in [root_host, "localhost", "127.0.0.1", "0.0.0.0"] do
        nil
      else
        String.replace(host, ~r/.?#{root_host}/, "")
        |> String.replace("api.", "")
      end
    end
  end
end
