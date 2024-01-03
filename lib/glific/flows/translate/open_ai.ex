defmodule Glific.Flows.Translate.OpenAI do
  @moduledoc """
  Code to translate using OpenAI as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate
  @open_ai_params %{"temperature" => 0, "max_tokens" => 12_000}
  @token_chunk_size 10_000

  alias Glific.OpenAI.ChatGPT

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
    strings = chunk(strings)

    strings
    |> Enum.reduce([], &[do_translate(&1, src, dst) | &2])
    |> Enum.flat_map(& &1)
    |> Enum.reverse()
    |> then(&{:ok, &1})
  end

  # Making API call to open ai to translate list of string from src language to dst
  @spec do_translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  defp do_translate(strings, src, dst) do
    length = Enum.count(strings)

    prompt =
      """
      I'm going to give you a template for your output. CAPTALIZED WORDS are my placeholders.
      Please preserve the overall formatting of my template to convert list of strings from #{src} to #{dst}

      ***["CONVERTED_TEXT_1", "CONVERTED_TEXT_2","CONVERTED_TEXT_3"]***

      Please return only the list. Here's sample

      User: ["hello there", "oops wrong answer", "Great to meet you"]
      Think: there are 3 comma separated strings list in english convert it to 3 comma separated list of string in hindi
      System: ["नमस्ते", "उफ़ ग़लत उत्तर", "बड़ा अच्छा लगा आपसे मिल के"]
      User: ["welcome", "correct answer, keep it up", "you won 1 point"]
      Think: there are 3 comma separated strings list in english convert it to 3 comma separated strings list in tamil
      System: ["வரவேற்பு", "சரியான பதில், தொடருங்கள்", "நீங்கள் 1 புள்ளியை வென்றீர்கள்"]
      """

    Glific.get_open_ai_key()
    |> ChatGPT.parse(
      """
      #{prompt}
      User: #{strings}
      Think: there are #{length} comma separated strings list in #{src} convert it to #{length} comma separated strings list in #{dst}
      System:
      """,
      @open_ai_params
    )
    |> case do
      {:ok, result} -> Jason.decode!(result)
      rest -> rest
    end
  end

  # Chunking list of strings based on the size
  @spec chunk([String.t()]) :: [String.t()]
  defp chunk(strings), do: do_chunk(strings, [], 0, [])

  @spec do_chunk([String.t()], list(), non_neg_integer(), list()) :: [String.t()]
  defp do_chunk([], chunk, _, acc), do: Enum.reverse([chunk | acc])

  defp do_chunk([head | tail], chunk, current_size, acc) do
    string_size = Gpt3Tokenizer.token_count(head)

    cond do
      # here we are ignoring long texts which have token count more than threshold
      string_size > @token_chunk_size ->
        do_chunk(tail, [], current_size, acc)

      # based on total size we are determining if we can do translation in single call or multiple calls
      current_size + string_size > @token_chunk_size ->
        do_chunk([head | tail], [], 0, [chunk | acc])

      true ->
        do_chunk(tail, [head | chunk], current_size + string_size, acc)
    end
  end
end
