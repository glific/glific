defmodule Glific.EncryptedMapType do
  @moduledoc """
  Cloak for encrypting maps
  """
  use Cloak.Ecto.Map, vault: Glific.Vault
end
