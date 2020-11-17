defmodule Glific.Encrypted.Binary do
  @moduledoc """
  Cloak for encrypting strings
  """
  use Cloak.Ecto.Binary, vault: Glific.Vault
end
