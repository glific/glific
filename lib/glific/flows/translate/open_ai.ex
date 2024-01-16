defmodule Glific.Flows.Translate.OpenAI do
  @moduledoc """
  Code to translate using OpenAI as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate
  @open_ai_params %{"temperature" => 0, "max_tokens" => 12_000}
  @token_chunk_size 200

  alias Glific.OpenAI.ChatGPT
  require Logger

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message

  ## Examples

  iex> Glific.Flows.Translate.OpenAI.translate(["thankyou for joining", "correct answer"], "english", "hindi")
    {:ok, ["hindi thankyou for joining english", "hindi correct answer english"]}
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst) do
    strings
    |> check_large_strings()
    |> Task.async_stream(fn text -> do_translate(text, src, dst) end)
    |> Enum.reduce([], fn {:ok, translated_text}, acc -> [translated_text | acc] end)
    |> then(&{:ok, &1})
  end

  # Making API call to open ai to translate list of string from src language to dst
  @spec do_translate([String.t()], String.t(), String.t()) :: [String.t()] | {:error, String.t()}
  defp do_translate(strings, src, dst) do
    prompt =
      """
      Translate the text from #{src} to #{dst}. Return only translated text
      User: "hello there"
      Think: Translate the text from english to hindi
      System: "नमस्ते"
      User: "you won 1 point"
      Think: Translate the text from english to tamil
      System: "நீங்கள் 1 புள்ளியை வென்றீர்கள்"
      """

    Glific.get_open_ai_key()
    |> ChatGPT.parse(
      """
      #{prompt}
      User: #{strings}
      Think: Translate the text from #{src} to #{dst}
      System:
      """,
      @open_ai_params
    )
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
      string_size = Gpt3Tokenizer.token_count(string)

      if string_size > @token_chunk_size do
        ["translation not available for long messages" | acc]
      else
        [string | acc]
      end
    end)
  end
end
