defmodule GlificWeb.SubdomainPlugConfig do
  @moduledoc """
  This is a struct that holds the configuration for `GlificWeb.SubdomainPlug`.

  Here are the config keys allowed:

  - `organization_handler`: function to handle the organization param. Its return will
  be used as the organization.
  - `assign`: the name of the assign where we must save the organization.
  - `endpoint`: the Phoenix.Endpoint to get the host name to dicover the
  subdomain.
  """
  @type t :: %__MODULE__{}

  @doc false
  defstruct [
    endpoint: GlificWeb.Endpoint,
    organization_handler: &GlificWeb.Tenants.organization_handler/1,
    assign: :organization_id
  ]
end
