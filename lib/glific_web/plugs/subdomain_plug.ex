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
      subdomain = get_subdomain(conn, config)

      # we allow nil subdomains while testing for now
      if is_nil(subdomain) && Application.get_env(:glific, :environment) != :test,
        do: Plug.send_error(conn),
        else: Plug.put_organization(conn, subdomain, config)
    end

    @doc """
    The organization id a request host belongs to, resolved as `call/2` does for a `conn`; for
    callers with no `conn`, such as a WebSocket connect.
    """
    @spec organization_id_for_host(String.t() | nil) :: {:ok, non_neg_integer()} | :error
    def organization_id_for_host(host) do
      config = struct(SubdomainPlugConfig)
      subdomain = subdomain_for_host(host, config.endpoint)

      with false <- is_nil(subdomain) and Application.get_env(:glific, :environment) != :test,
           false <- subdomain != nil and GlificWeb.Tenants.reserved_organization?(subdomain),
           id when id != 0 <- config.organization_handler.(subdomain) do
        {:ok, id}
      else
        _unresolved -> :error
      end
    end

    @spec get_subdomain(Conn.t(), map()) :: String.t() | nil
    defp get_subdomain(_conn, %SubdomainPlugConfig{endpoint: nil}), do: nil

    defp get_subdomain(%Conn{host: host}, %SubdomainPlugConfig{endpoint: endpoint}),
      do: subdomain_for_host(host, endpoint)

    @spec subdomain_for_host(String.t() | nil, module()) :: String.t() | nil
    defp subdomain_for_host(host, endpoint) when is_binary(host) do
      root_host = endpoint.config(:url)[:host]
      glific_subdomain = Glific.base_domain()

      cond do
        host in ["0.0.0.0", "www.example.com", "glific.gigalixirapp.com"] ->
          nil

        # this is just a temporary fix for now to get CI up and running
        # we need a better long term solution soon
        host in ["localhost", root_host, "127.0.0.1"] ->
          "glific"

        String.ends_with?(host, glific_subdomain) ->
          host
          |> String.replace(~r/.?#{glific_subdomain}/, "")
          |> String.replace("api.", "")

        true ->
          host
          |> String.replace(~r/.?#{root_host}/, "")
          |> String.replace("api.", "")
      end
    end

    defp subdomain_for_host(_host, _endpoint), do: nil
  end
end
