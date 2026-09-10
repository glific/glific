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
    assert message =~ "Line 2 of the file is not valid UTF-8"
    assert message =~ "CSV UTF-8"
  end

  test "rejects UTF-16 with its own message" do
    utf16 = :unicode.characters_to_binary(@body, :utf8, {:utf16, :little})

    # UTF-16 of ascii is valid UTF-8, so only the NUL bytes give it away
    assert String.valid?(utf16)
    assert {:error, message} = Encoding.validate(utf16)
    assert message =~ "NUL bytes"
    assert message =~ "UTF-16 or UTF-32"
  end

  test "strip_bom removes the BOM from the first line only" do
    assert ["question,answer", "q1," <> @bom <> "a1"] ==
             [@bom <> "question,answer", "q1," <> @bom <> "a1"]
             |> Encoding.strip_bom()
             |> Enum.to_list()
  end

  describe "strip_bom_from_file/1" do
    setup do
      path = Path.join(System.tmp_dir!(), "encoding_#{System.unique_integer([:positive])}.csv")
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "rewrites the file without its BOM", %{path: path} do
      File.write!(path, @bom <> @body)

      assert :ok == Encoding.strip_bom_from_file(path)
      assert @body == File.read!(path)
    end

    test "leaves a file without a BOM untouched", %{path: path} do
      File.write!(path, @body)

      assert :ok == Encoding.strip_bom_from_file(path)
      assert @body == File.read!(path)
    end

    test "reports an unreadable path instead of raising" do
      assert {:error, :enoent} == Encoding.strip_bom_from_file("/nonexistent/file.csv")
    end
  end
end
