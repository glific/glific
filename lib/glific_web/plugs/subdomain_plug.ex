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

    defp send_error(conn) do
      conn
      |> Conn.put_status(403)
      |> Conn.send_resp(403, "Unauthorized")
      |> Conn.halt()
    end

    @doc false
    @spec call(Conn.t(), map()) :: Conn.t()
    def call(conn, config) do
      subdomain = get_subdomain(conn, config)

      # we allow nil subdom,ains while testing for now
      if is_nil(subdomain) && Application.get_env(:glific, :environment) != :test,
        do: send_error(conn),
        else: Plug.put_organization(conn, subdomain, config)
    end

    @spec get_subdomain(Conn.t(), map()) :: String.t() | nil
    defp get_subdomain(_conn, %SubdomainPlugConfig{endpoint: nil}), do: nil

    defp get_subdomain(
           %Conn{host: host},
           %SubdomainPlugConfig{endpoint: endpoint}
         ) do
      root_host = endpoint.config(:url)[:host]

      cond do
        host in ["0.0.0.0", "www.example.com", "glific.gigalixirapp.com"] ->
          nil

        # this is just a temporary fix for now to get CI up and running
        # we need a better long term solution soon
        host in ["localhost", root_host, "127.0.0.1"] ->
          "glific"

        true ->
          host
          |> String.replace(~r/.?#{root_host}/, "")
          |> String.replace("api.", "")
      end
    end
  end
end
