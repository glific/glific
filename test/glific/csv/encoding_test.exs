defmodule Glific.CSV.EncodingTest do
  use ExUnit.Case, async: true

  alias Glific.CSV.Encoding

  @body "question,answer\nq1,fee is 10 – 20 and he said “hi”\n"

  defp lines(contents), do: String.split(contents, "\n")

  test "accepts UTF-8, with or without a BOM" do
    assert :ok == Encoding.validate(@body)
    assert :ok == Encoding.validate(<<0xEF, 0xBB, 0xBF>> <> @body)
    assert :ok == Encoding.validate(lines(@body))
  end

  test "rejects Windows codepage bytes and reports the line" do
    cp1252 = <<"question,answer\nq1,fee is 10 ", 0x96, " 20\n">>

    assert {:error, message} = Encoding.validate(cp1252)
    assert message =~ "Line 2 of the file is not valid UTF-8"
    assert message =~ "CSV UTF-8"
  end

  test "rejects UTF-16 with its own message" do
    utf16 = :unicode.characters_to_binary(@body, :utf8, {:utf16, :little})

    assert {:error, message} = Encoding.validate(utf16)
    assert message =~ "UTF-16 or UTF-32"
  end

  test "strip_bom removes the BOM from the first line only" do
    bom = <<0xEF, 0xBB, 0xBF>>

    assert ["question,answer", "q1," <> bom <> "a1"] ==
             [bom <> "question,answer", "q1," <> bom <> "a1"]
             |> Encoding.strip_bom()
             |> Enum.to_list()
  end
end
