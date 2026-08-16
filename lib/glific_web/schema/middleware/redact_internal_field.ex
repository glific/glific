defmodule GlificWeb.Schema.Middleware.RedactInternalField do
  @moduledoc """
  Resolves a field to nil without reading the stored value.

  Applied by `GlificWeb.Schema.middleware/3` to every field listed in
  `Glific.Partners.Organization.internal_fields/0`, so a setting is withdrawn from the API by
  naming it there rather than by editing each type module.
  """

  @behaviour Absinthe.Middleware

  @doc """
  Short-circuits resolution with nil, replacing the field's usual resolver.
  """
  @spec call(Absinthe.Resolution.t(), term()) :: Absinthe.Resolution.t()
  def call(resolution, _config),
    do: Absinthe.Resolution.put_result(resolution, {:ok, nil})
end
