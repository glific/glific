defmodule Glific.Flows.Translate.Translate do
  @moduledoc """
  This module is the behavior interface for translation

  The rest of the code uses this as the API and is unaware of who the underlying
  translation API provider is
  """

  alias Glific.{
    Flags,
    Flows.Translate.GoogleTranslate,
    Flows.Translate.OpenAI,
    Flows.Translate.Simple,
    Settings
  }

  @doc """
  Lets define the behavior callback that everyone should follow
  """
  @callback translate(strings :: [String.t()], src :: String.t(), dst :: String.t()) ::
              {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  API interface for all modules to call the translate function. We'll use Elixir Config for this
  during deployment. For now, we have only one translator
  """
  @spec translate([String.t()], String.t(), String.t(), map()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst, organization) do
    translation_engine = impl(organization)

    case translation_engine do
      OpenAI ->
        OpenAI.translate(strings, src, dst)

      GoogleTranslate ->
        language = Settings.locale_label_map(organization.id)

        language_code =
          Enum.reduce(language, %{}, fn {key, value}, acc ->
            Map.put(acc, value, key)
          end)

        src_lang_code = Map.get(language_code, src, src)
        dst_lang_code = Map.get(language_code, dst, dst)
        GoogleTranslate.translate(strings, src_lang_code, dst_lang_code)

      _ ->
        Simple.translate(strings, src, dst)
    end
  end

  defp impl(organization) do
    cond do
      Flags.get_open_ai_auto_translation_enabled(organization) ->
        OpenAI

      Flags.get_google_auto_translation_enabled(organization) ->
        GoogleTranslate

      true ->
        Application.get_env(:glific, :adaptors)[:translators]
    end
  end

  @doc """
  Lets make a simple function to translate one string
  """
  @spec translate_one!(String.t(), String.t(), String.t(), map()) :: String.t()
  def translate_one!(orig, src, dst, organization) do
    {:ok, result} = translate([orig], src, dst, organization)
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
