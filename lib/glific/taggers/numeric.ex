defmodule Glific.Taggers.Numeric do
  @moduledoc """
  The numeric tagger which takes the message body and checks if the body is mainly a number in different ways including:
    Ordinal Numbers (0..19)
    Cardinal Number (Zero - Ten)
    Emojis (0..9)
    Ordinal Hindi Numbers
    Cardinal Hindi Numbers
  """

  alias Glific.{
    Messages.Message,
    Taggers
  }

  # Our initial map which stores the mappings we love and adore
  @numeric_map %{
    # 0..9
    "0" => 0,
    "1" => 1,
    "2" => 2,
    "3" => 3,
    "4" => 4,
    "5" => 5,
    "6" => 6,
    "7" => 7,
    "8" => 8,
    "9" => 9,

    # 10..19
    "10" => 10,
    "11" => 11,
    "12" => 12,
    "13" => 13,
    "14" => 14,
    "15" => 15,
    "16" => 16,
    "17" => 17,
    "18" => 18,
    "19" => 19,

    # zero..ten
    "zero" => 0,
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9,
    "ten" => 10,

    # hindi numbers 0..10
    "\u0966" => 0,
    "\u0967" => 1,
    "\u0968" => 2,
    "\u0969" => 3,
    "\u096A" => 4,
    "\u096B" => 5,
    "\u096C" => 6,
    "\u096D" => 7,
    "\u096E" => 8,
    "\u096F" => 9,
    "\u0967\u0966" => 10,

    # hindi ordinals in english
    "shunya" => 0,
    "ek" => 1,
    "do" => 2,
    "teen" => 3,
    "char" => 4,
    "panch" => 5,
    "cheh" => 6,
    "saat" => 7,
    "aath" => 8,
    "nao" => 9,
    "das" => 10,

    # hindi ordinals in hindi
    "शून्य" => 0,
    "एक" => 1,
    "दो" => 2,
    "तीन" => 3,
    "चार" => 4,
    "पांच" => 5,
    "छह" => 6,
    "सात" => 7,
    "आठ" => 8,
    "नौ" => 9,

    # emojis as numbers
    to_string(['\u0030', 65_039, 8419]) => 0,
    to_string(['\u0031', 65_039, 8419]) => 1,
    to_string(['\u0032', 65_039, 8419]) => 2,
    to_string(['\u0033', 65_039, 8419]) => 3,
    to_string(['\u0034', 65_039, 8419]) => 4,
    to_string(['\u0035', 65_039, 8419]) => 5,
    to_string(['\u0036', 65_039, 8419]) => 6,
    to_string(['\u0037', 65_039, 8419]) => 7,
    to_string(['\u0038', 65_039, 8419]) => 8,
    to_string(['\u0039', 65_039, 8419]) => 9
  }

  @doc false
  @spec get_numeric_map :: %{String.t() => integer}
  def get_numeric_map, do: @numeric_map

  @doc false
  @spec tag_message(Message.t(), %{String.t() => integer}) :: {:ok, String.t()} | :error
  def tag_message(message, numeric_map) do
    message.body
    |> Taggers.string_clean()
    |> tag_body(numeric_map)
  end

  @doc false
  @spec tag_body(String.t(), %{String.t() => integer}) :: {:ok, String.t()} | :error
  def tag_body(body, numeric_map) do
    case Map.fetch(numeric_map, body) do
      {:ok, value} -> {:ok, to_string(value)}
      _ -> :error
    end
  end
end
