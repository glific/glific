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

  defp impl, do: Application.get_env(:glific, :adaptors)[:translators]

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message
  """
  @spec translate_one(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def translate_one(string, src, dst) do
    case translate([string], src, dst) do
      {:ok, result} -> {:ok, hd(result)}
      rest -> rest
    end
  end
end
