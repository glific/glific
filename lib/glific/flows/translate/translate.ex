defmodule Glific.Flows.Translate.Translate do
  @moduledoc """
  This module is the behavior interface for translation

  The rest of the code uses this as the API and is unaware of who the underlying
  translation API provider is
  """
  @callback translate(strings :: [String.t()], src :: String.t(), dst :: String.t()) ::
              {:ok, [String.t()]} | {:error, String.t()}

  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst), do: impl().translate(strings, src, dst)

  # defp impl, do: Application.get_env(:glific, :adaptors)[:translators]
  defp impl, do: Glific.Flows.Translate.OpenAI
end
