defmodule Glific.Vault do
  @moduledoc """
  Cloak Vault
  """
  use Cloak.Vault, otp_app: :glific
  @impl GenServer
  @spec init([key: value_type] :: {:ok , [key: value_type]})
  def init(config) do
    config =
      Keyword.put(config, :ciphers, [
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!("CLOAK_KEY")}
      ])

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
