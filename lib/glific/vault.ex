defmodule Glific.Vault do
  @moduledoc """
  Cloak Vault
  """
  use Cloak.Vault, otp_app: :glific

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers, [
        default:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V2", key: Base.decode64!("ojQBZB6XbSeJVkWXBOrg81p/snOaQ7JlGgSPSPK09KQ=")},
        retired:
          {Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: Base.decode64!("BliS4zyqMG065ZrRJ8BhhruZFXnpV+eYAQBRqzusnSY=")}
      ])

    {:ok, config}
  end
end
