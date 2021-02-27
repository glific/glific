if Code.ensure_loaded?(Plug) do
  defmodule GlificWeb.Plug do
    @moduledoc """
    This file and the below files have been "borrowed and modified" from triplex: https://github.com/ateliware/triplex
    The original copyright and license - MIT belong to the authors and contributors of Triplex

      * plug.ex
      * ensure_plug.ex
      * ensure_plug_config.ex
      * subdomain_plug.ex
      * subdomain_plug_config.ex
      * param_plug.ex
      * param_plug_config.ex

    This module have some basic functions for our triplex plugs.

    The plugs we have for now are:

    - `GlificWeb.ParamPlug` - loads the organization from a body or query param
    - `GlificWeb.SubdomainPlug` - loads the organization from the url subdomain
    - `GlificWeb.EnsurePlug` - ensures the current organization is loaded and halts if not
    """

    alias Plug.Conn

    require Logger

    @raw_organization_assign :raw_organization_name

    @doc """
    Global unauthorized error handler
    """
    @spec send_error(Conn.t()) :: Conn.t()
    def send_error(conn) do
      conn
      |> Conn.put_status(403)
      |> Conn.send_resp(403, "Unauthorized")
      |> Conn.halt()
    end

    @doc """
    Puts the given `organization` as an assign on the given `conn`, but only if the
    organization is not reserved.

    The `config` map/struct must have:

    - `organization_handler`: function to handle the organization param. Its return will
    be used as the organization.
    - `assign`: the name of the assign where we must save the organization.
    """
    @spec put_organization(Conn.t(), any(), map()) :: Conn.t()
    def put_organization(conn, organization, config) do
      if conn.assigns[config.assign] do
        conn
      else
        conn = Conn.assign(conn, @raw_organization_assign, organization)
        organization_id = organization_handler(organization, config.organization_handler)

        cond do
          GlificWeb.Tenants.reserved_organization?(organization) ->
            conn

          organization_id == 0 ->
            Logger.info("Halting on failure to retrive #{organization}")
            send_error(conn)

          true ->
            Glific.Repo.put_organization_id(organization_id)
            Conn.assign(conn, config.assign, organization_id)
        end
      end
    end

    @doc """
    Ensure the organization is loaded, and if not, halts the `conn`.

    The `config` map/struct must have:

    - `assign`: the name of the assign where we must save the organization.
    """
    @spec ensure_organization(Conn.t(), map()) :: Conn.t()
    def ensure_organization(conn, config) do
      if loaded_organization = conn.assigns[config.assign] do
        callback(conn, loaded_organization, config.callback)
      else
        conn
        |> callback(conn.assigns[@raw_organization_assign], config.failure_callback)
        |> send_error()
      end
    end

    @spec organization_handler(any(), any()) :: any()
    defp organization_handler(organization, nil),
      do: organization

    defp organization_handler(organization, handler) when is_function(handler),
      do: handler.(organization)

    defp callback(conn, _, nil),
      do: conn

    defp callback(conn, organization, callback) when is_function(callback),
      do: callback.(conn, organization)
  end
end
