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

  defstruct [
    :endpoint,
    :organization_handler,
    assign: :current_organization
  ]
end
