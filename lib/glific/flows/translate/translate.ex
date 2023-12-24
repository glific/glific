defmodule Glific.Flows.Translate.Translate do
  @moduledoc """
  This module is the behavior interface for translation

  The rest of the code uses this as the API and is unaware of who the underlying
  translation API provider is
  """

  @doc """
  Lets define the behavior callback that everyone should follow
  """
  @callback translate(strings :: [String.t()], src :: String.t(), dst :: String.t()) ::
              {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  API interface for all modules to call the translate function. We'll use Elixir Config for this
  during deployment. For now, we have only one translator
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst), do: impl().translate(strings, src, dst)

  # defp impl, do: Application.get_env(:glific, :adaptors)[:translators]
  defp impl, do: Glific.Flows.Translate.OpenAI
end
