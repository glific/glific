defmodule Glific.Flows.Translate.GoogleTranslate do
  @moduledoc """
  Code to translate using google translate as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate
  @google_translate_params %{"temperature" => 0, "max_tokens" => 12_000}
  @token_chunk_size 200

  alias Glific.GoogleTranslate.Translate
  require Logger


  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message

  ## Examples

  iex> Glific.Flows.Translate.GoogleTranslate.translate(["thankyou for joining", "correct answer"], "en", "hi")
    {:ok, ["hindi thankyou for joining english", "hindi correct answer english"]}
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst) do
    strings
    |> check_large_strings()
    |> Enum.reduce([], &[do_translate(&1, src, dst) | &2])
    |> then(&{:ok, &1})
  end

  # Making API call to google translate to translate list of string from src language to dst
  @spec do_translate([String.t()], String.t(), String.t()) :: [String.t()] | {:error, String.t()}
  defp do_translate(strings, src, dst) do
    api_key = "AIzaSyCvRM-GQMS3XoUpmTM2EVjpMoLO0G3Ix9c"
    Translate.parse(api_key, strings, src, dst, @google_translate_params)
    |> case do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Error translating: #{error} String: #{strings}")
        ["Could not translate, Try again"]
    end
  end

  @doc """
  Cleanup up string list replacing long text exceeding token threshold with warning
  This reverses the order of string which is reversed again in next function
  """
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
