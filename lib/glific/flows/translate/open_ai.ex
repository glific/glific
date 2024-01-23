defmodule Glific.Flows.Translate.OpenAI do
  @moduledoc """
  Code to translate using OpenAI as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate
  @open_ai_params %{"temperature" => 0, "max_tokens" => 12_000}
  @token_chunk_size 200

  alias Glific.Flows.Translate.Translate
  alias Glific.OpenAI.ChatGPT
  require Logger

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message

  ## Examples

  iex> Glific.Flows.Translate.OpenAI.translate(["thankyou for joining", "correct answer"], "english", "hindi")
    {:ok, ["शामिल होने के लिए धन्यवाद", "सही जवाब"]}
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst) do
    strings
    |> Translate.check_large_strings()
    |> Task.async_stream(fn text -> do_translate(text, src, dst) end,
      timeout: 300_000,
      max_concurrency: 15,
      # send {:exit, :timeout} so it can be handled
      on_timeout: :kill_task
    )
    |> Enum.reduce([], fn response, acc ->
      handle_async_response(response, acc)
    end)
    |> then(&{:ok, &1})
  end

  # add the translated string into list of string if translated successfully
  # add the empty string into list of string if translation timed out so it can be translated in next go
  # This way successfully translated string will be updated in first go and leftover will be translated in second go
  @spec handle_async_response(tuple(), [String.t()]) :: [String.t()]
  defp handle_async_response({:ok, translated_text}, acc), do: [translated_text | acc]
  defp handle_async_response({:exit, :timeout}, acc), do: ["" | acc]

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
        ""
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
