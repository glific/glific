defmodule Glific.Taggers.Numeric do
  @moduledoc """
  The numeric tagger which takes the message body and checks if the body is mainly a number in different ways including:
    Ordinal Numbers (0..19)
    Cardinal Number (Zero - Ten)
    Emojis (0..9)
    Ordinal Hindi Numbers
    Cardinal Hindi Numbers
  """

  alias Glific.Taggers

  @numeric_map %{
    # 0..9
    "0" => 0, "1" => 1, "2" => 2, "3" => 3, "4" => 4,
    "5" => 5, "6" => 6, "7" => 7, "8" => 8, "9" => 9,

    # 10..19
    "10" => 10, "11" => 11, "12" => 12, "13" => 13, "14" => 14,
    "15" => 15, "16" => 16, "17" => 17, "18" => 18, "19" => 19,

    # zero..ten
    "zero" => 0, "one" => 1, "two" => 2, "three" => 3, "four" => 4,
    "five" => 5, "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9,
    "ten" => 10,

    # hindi numbers 0..10
    "\U0966" => 0, "\U0967" => 1, "\U0968" => 2, "\U0969" => 3, "\U096A" => 4,
    "\U096B" => 5, "\U096C" => 6, "\U096D" => 7, "\U096E" => 8,"\U096F" => 9,
    "\U0967\U0966" => 10,

    # hindi ordinals in english
    "shunya" => 0, "ek" => 1, "do" => 2, "teen" => 3, "char" => 4,
    "panch" => 5, "cheh" => 6, "saat" => 7, "aath" => 8, "nao" => 9,
    "das" => 10,

    # hindi ordinals in hindi
    "शून्य" => 0, "एक" => 1, "दो" => 2, "तीन" => 3, "चार" => 4,
    "पांच" => 5, "छह" => 6, "सात" => 7, "आठ" => 8, "नौ" => 9,

    # emojis as numbers
    "\U0030\UFEOF\U20E3" => 0, "\U0031\UFEOF\U20E3" => 1,
    "\U0032\UFEOF\U20E3" => 2, "\U0033\UFEOF\U20E3" => 3,
    "\U0034\UFEOF\U20E3" => 4, "\U0035\UFEOF\U20E3" => 5,
    "\U0036\UFEOF\U20E3" => 6, "\U0037\UFEOF\U20E3" => 7,
    "\U0038\UFEOF\U20E3" => 8, "\U0039\UFEOF\U20E3" => 9
  }

  @spec get_numeric_map() :: %{String.t() => integer}
  def get_numeric_map(), do: @numeric_map

  @spec tag_message(Message.t(), %{String.t() => integer}) :: {:ok, String.t()} | :error
  def tag_message(message, numeric_map) do
    body =
      message.body
      |> Taggers.string_clean

    case Map.fetch(numeric_map, body) do
      {:ok, value} -> {:ok, to_string(value)}
      :error -> :error
    end
  end
end
