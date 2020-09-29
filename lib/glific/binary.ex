defmodule Glific.Encrypted.Binary do
  @moduledoc """
  Cloak for encrypting maps
  """
  use Cloak.Ecto.Binary, vault: Glific.Vault
end
