defmodule Glific.CSV.Encoding do
  @moduledoc """
  Guards CSV ingest against files that are not valid UTF-8.

  Spreadsheet apps write `.csv` in whatever encoding the export menu picked, and the
  extension records none of it. Google Sheets and Excel's "CSV UTF-8" give us UTF-8;
  Excel's plain "CSV (Comma delimited)" gives us the Windows codepage of the machine
  it ran on, and "Unicode Text" gives us UTF-16. Only UTF-8 survives our pipeline —
  Postgres rejects the rest at insert time — so reject the others up front with a
  message that names the fix.
  """

  @bom <<0xEF, 0xBB, 0xBF>>

  @resave_hint "Re-save the file as UTF-8: in Excel use File → Save As → " <>
                 "\"CSV UTF-8 (Comma delimited)\", or in Google Sheets use File → Download → " <>
                 "\"Comma-separated values (.csv)\"."

  @utf16_error "The file looks like UTF-16 or UTF-32 text, which we cannot read " <>
                 "(Excel's \"Unicode Text\" export writes this). " <> @resave_hint

  @doc """
  Check that a CSV is valid UTF-8, accepting either the raw contents or a line stream.
  """
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
  Strip the leading UTF-8 BOM that Excel's "CSV UTF-8" export writes.
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
