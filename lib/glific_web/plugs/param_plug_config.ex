defmodule GlificWeb.ParamPlugConfig do
  @moduledoc """
  This is a struct that holds all configuration for `GlificWeb.ParamPlug`.

  Here are the config keys allowed:

  - `organization_handler`: function to handle the organization param. Its return will
  be used as the organization.
  - `assign`: the name of the assign where we must save the organization.
  - `param`: the param name to load the organization from.
  """
  @type t :: %__MODULE__{}
  @doc false
  defstruct [
    organization_handler: &GlificWeb.Tenants.organization_handler/1,
    assign: :organization_id,
    param: "organization"
  ]
end
