defmodule Glific.CSV.EncodingTest do
  @moduledoc """
  Covers the UTF-8 gate every CSV upload path goes through, and BOM removal.
  """
  use ExUnit.Case, async: true

  alias Glific.CSV.Encoding

  @bom <<0xEF, 0xBB, 0xBF>>
  @body "question,answer\nq1,fee is 10 – 20 and he said “hi”\n"

  test "accepts UTF-8, with or without a BOM" do
    assert :ok == Encoding.validate(@body)
    assert :ok == Encoding.validate(@bom <> @body)
    assert :ok == Encoding.validate(String.split(@body, "\n"))
  end

  test "rejects Windows codepage bytes and reports the line" do
    cp1252 = <<"question,answer\nq1,fee is 10 ", 0x96, " 20\n">>

    assert {:error, message} = Encoding.validate(cp1252)
    assert message =~ "Line 2 is not valid UTF-8"
    assert message =~ "CSV UTF-8"
  end

  test "rejects UTF-16 with its own message" do
    utf16 = :unicode.characters_to_binary(@body, :utf8, {:utf16, :little})

    # UTF-16 of ascii is valid UTF-8, so only the NUL bytes give it away
    assert String.valid?(utf16)
    assert {:error, message} = Encoding.validate(utf16)
    assert message =~ "UTF-16 or UTF-32, not UTF-8"
  end

  test "strip_bom removes a leading BOM and leaves the rest of the line" do
    assert ["question,answer", "q1," <> @bom <> "a1"] ==
             [@bom <> "question,answer", "q1," <> @bom <> "a1"]
             |> Encoding.strip_bom()
             |> Enum.to_list()
  end
end
