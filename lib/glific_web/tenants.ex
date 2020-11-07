defmodule GlificWeb.Tenants do
  @moduledoc """
  This is the main module of multi-tenancy in Glific. It has been borrowed from
  Triplex. (https://github.com/ateliware/triplex). However we are going to us
  postgres row level security instead, and hence copying the code from there. The
  original copyright and license (MIT) belong to the contributors to Triplex.

  The main objetive of it is to make a little bit easier to manage organizations
  through postgres db schemas or equivalents, executing queries and commands
  inside and outside the organization without much boilerplate code.
  """

  alias Glific.{
    Partners.Organization,
    Repo
  }

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
      if is_bitstring(prefix) and Regex.regex?(i) do
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
    {:ok, default} = Repo.fetch_by(Organization, %{shortcode: "glific"})
    default.id
  end

  def organization_handler(shortcode) do
    case Repo.fetch_by(Organization, %{shortcode: shortcode}) do
      {:ok, organization} ->
        organization.id

      # in the normal case we'll redirect them here to glific.io
      # and halt this connection
      _ ->
        organization_handler()
    end
  end
end
