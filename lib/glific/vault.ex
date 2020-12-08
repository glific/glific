defmodule Glific.Vault do
  @moduledoc """
  Cloak Vault
  """
  use Cloak.Vault, otp_app: :glific

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V2", key: decode_env!("NEW_CIPHER_KEY")},
        old_key: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!("CIPHER_KEY")}
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
