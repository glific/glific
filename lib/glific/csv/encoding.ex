defmodule Glific.CSV.Encoding do
  @moduledoc """
  Rejects CSV uploads that are not valid UTF-8.

  `.csv` records no encoding, so the bytes depend on the export: Google Sheets and
  Excel's "CSV UTF-8" give UTF-8, Excel's plain "CSV (Comma delimited)" gives a
  Windows codepage and "Unicode Text" gives UTF-16. Only UTF-8 survives the
  pipeline, so the rest are rejected here with a message naming the fix.
  """

  @bom <<0xEF, 0xBB, 0xBF>>

  @resave_hint "Re-save the file as UTF-8: in Excel use File → Save As → " <>
                 "\"CSV UTF-8 (Comma delimited)\", or in Google Sheets use File → Download → " <>
                 "\"Comma-separated values (.csv)\"."

  @utf16_error "The file looks like UTF-16 or UTF-32 text, which we cannot read " <>
                 "(Excel's \"Unicode Text\" export writes this). " <> @resave_hint

  @doc "Check a CSV is valid UTF-8, given either its raw contents or a line stream."
  @spec validate(binary() | Enumerable.t()) :: :ok | {:error, String.t()}
  def validate(contents) when is_binary(contents),
    do: contents |> String.split("\n") |> validate()

  def validate(lines) do
    lines
    |> Stream.with_index(1)
    |> Enum.reduce_while(:ok, fn {line, row}, _acc ->
      cond do
        String.contains?(line, <<0>>) -> {:halt, {:error, @utf16_error}}
        String.valid?(line) -> {:cont, :ok}
        true -> {:halt, {:error, invalid_byte_error(row)}}
      end
    end)
  end

  @doc """
  Strip the leading byte order mark (BOM) that Excel's "CSV UTF-8" export writes.

  A BOM is valid UTF-8, so `validate/1` cannot catch it, but it corrupts the first
  header of the row it precedes.
  """
  @spec strip_bom(Enumerable.t()) :: Enumerable.t()
  def strip_bom(lines) do
    lines
    |> Stream.with_index()
    |> Stream.map(fn
      {line, 0} -> String.replace_prefix(line, @bom, "")
      {line, _row} -> line
    end)
  end

  @spec invalid_byte_error(pos_integer()) :: String.t()
  defp invalid_byte_error(row) do
    "Line #{row} of the file is not valid UTF-8. This usually means a smart quote, " <>
      "apostrophe, dash or accented letter was saved in a Windows encoding. " <> @resave_hint
  end
end
