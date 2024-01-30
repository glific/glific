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
  defp impl, do: Application.get_env(:glific, :adaptors)[:translators]

  @doc """
  Lets make a simple function to translate one string
  """
  @spec translate_one!(String.t(), String.t(), String.t()) :: String.t()
  def translate_one!(orig, src, dst) do
    {:ok, result} = translate([orig], src, dst)
    hd(result)
  end

  @doc """
  Cleanup up string list replacing long text exceeding token threshold with warning
  This reverses the order of string which is reversed again in next function
  """
  @token_chunk_size 200
  @spec check_large_strings([String.t()]) :: [String.t()]
  def check_large_strings(strings) do
    strings
    |> Enum.reduce([], fn string, acc ->
      # we ca use the gptTokenizer to count the token
      string_size = Gpt3Tokenizer.token_count(string)

      if string_size > @token_chunk_size do
        ["translation not available for long messages" | acc]
      else
        [string | acc]
      end
    end)
  end
end
