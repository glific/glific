defmodule GlificWeb.Tenants do
  @moduledoc """
  This is the main module of multi-tenancy in Glific. It has been borrowed from
  Triplex. (https://github.com/ateliware/triplex). However we are going to us
  postgres row level security instead, and hence copying the code from there. The
  original copyright and license (MIT) belong to the contributors to Triplex.

  The main objective of it is to make a little bit easier to manage organizations
  through postgres db schemas or equivalents, executing queries and commands
  inside and outside the organization without much boilerplate code.
  """

  alias Glific.Partners

  @doc """
  Returns the list of reserved organizations.

  By default, there are some limitations for the name of a organization depending on
  the database, like "public" or anything that start with "pg_".

  Notice that you can use regexes, and they will be applied to the organization
  names.
  """
  @spec reserved_organizations() :: list()
  def reserved_organizations do
    [
      nil,
      "public",
      "information_schema",
      ~r/^pg_/,
      ~r/^db\d+$/,
      "www"
    ]
  end

  @doc """
  Returns if the given `organization` is reserved or not.

  The function `to_prefix/1` will be applied to the organization.
  """
  @spec reserved_organization?(String.t()) :: boolean()
  def reserved_organization?(prefix) do
    Enum.any?(reserved_organizations(), fn i ->
      if is_bitstring(prefix) and Kernel.is_struct(i, Regex) do
        Regex.match?(i, prefix)
      else
        i == prefix
      end
    end)
  end

  @doc """
  Given a string from the connection info (subdomain), check and
  retrieve the organization id.

  For the short term, we'll default to organization id Glific, if
  we cannot resolve the sub-domain, we'll remove this in v0.4
  """
  @spec organization_handler(String.t() | nil) :: integer
  def organization_handler(name \\ nil)

  def organization_handler(nil) do
    # in the normal case we'll redirect them here to glific.io
    # and halt this connection
    default = Partners.organization("glific")
    default.id
  end

  # lets keep api as the default edge case for our development environment
  # and redirect users to glific
  def organization_handler("api"), do: organization_handler()

  def organization_handler(shortcode) do
    case Partners.organization(shortcode) do
      # lets stop resolving nil to glific to avoid any potential security issues
      nil ->
        0

      # we assume 0 is the error for now
      {:error, _error} ->
        0

      # if not active or approved, lets return an error
      organization ->
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: organization.id,
          else: 0
    end
  end

  @doc """
  Given a conn object, get the remote ip of the user as a string
  """
  @spec remote_ip(Plug.Conn.t()) :: String.t()
  def remote_ip(conn) do
    conn.remote_ip
    |> :inet_parse.ntoa()
    |> to_string()
  end
end
