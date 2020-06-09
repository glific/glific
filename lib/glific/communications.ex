defmodule Glific.Communications do
  @spec effective_provider :: any
  def effective_provider() do
    with nil <- provider_per_organisation(),
         nil <- provider_from_config(),
         do: provider_default()
  end

  def organisation_contact() do
    with nil <- contact_per_organisation(),
         nil <- contact_from_config(),
         do: contact_default()
  end

  defp provider_per_organisation() do
    nil
  end

  defp provider_from_config() do
    case Application.fetch_env!(:two_way, :provider) do
      nil -> nil
      provider -> provider
    end
  end

  defp provider_default() do
    TwoWay.Communications.BSP.Twilio
  end

  defp contact_per_organisation() do
    nil
  end

  defp contact_from_config() do
    nil
  end

  defp contact_default() do
    # For sendbox only
    %{"source" => "917834811114", "src.name" => "NGO Name"}
  end
end
