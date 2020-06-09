defmodule Glific.Communications do
  @spec effective_provider :: any
  def effective_provider() do
    with nil <- provider_per_organisation(),
         nil <- provider_from_config(),
         do: provider_default()
  end

  defp provider_per_organisation() do
    nil
  end

  defp provider_from_config() do
    case Application.fetch_env!(:glific, :provider) do
      nil -> nil
      provider -> provider
    end
  end

  defp provider_default() do
    TwoWay.Communications.BSP.Twilio
  end
end
