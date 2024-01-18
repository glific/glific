defmodule Glific.Flows.Translate.GoogleTranslate do
  @moduledoc """
  Code to translate using google translate as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate
  @google_translate_params %{"temperature" => 0, "max_tokens" => 12_000}

  alias Glific.Flows.Translate.Translate
  require Logger

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message

  ## Examples

  iex> Glific.Flows.Translate.GoogleTranslate.translate(["thankyou for joining", "correct answer"], "en", "hi")
    {:ok,["शामिल होने के लिए धन्यवाद","सही जवाब"]}
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst) do
    strings
    |> Translate.check_large_strings()
    |> Task.async_stream(fn text -> do_translate(text, src, dst) end,
      timeout: 300_000,
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

  # Making API call to google translate to translate list of string from src language to dst
  @spec do_translate(String.t(), String.t(), String.t()) :: String.t() | {:error, String.t()}
  defp do_translate(strings, src, dst) do
    Glific.get_google_translate_key()
    |> Glific.GoogleTranslate.Translate.parse(strings, src, dst, @google_translate_params)
    |> case do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Error translating: #{error} String: #{strings}")
        ["Could not translate, Try again"]
    end
  end
end
