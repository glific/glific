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

  @nul_byte_error "The file contains NUL bytes, so it is not plain text — it is most " <>
                    "likely UTF-16 or UTF-32 (Excel's \"Unicode Text\" export writes this). " <>
                    @resave_hint

  @doc """
  Check a CSV is valid UTF-8, given either its raw contents or a line stream.

  A stream must carry one line per element (`File.stream!/1`, `IO.binstream(pid, :line)`) —
  a byte-chunked stream would split a multi-byte character across two elements and be
  rejected as invalid.
  """
  @spec validate(binary() | Enumerable.t()) :: :ok | {:error, String.t()}
  # String.splitter, not String.split: an upload is only bounded by the 20MB Plug.Parsers
  # limit, and String.split holds every line at once at ~56 bytes of list cell plus sub-binary
  # header each — 2MB of bare newlines measured at 111MB of heap.
  def validate(contents) when is_binary(contents),
    do: contents |> String.splitter("\n") |> validate()

  def validate(lines) do
    lines
    |> Stream.with_index(1)
    |> Enum.reduce_while(:ok, fn {line, row}, _acc ->
      cond do
        # UTF-16 of ASCII is valid UTF-8 (`<<113, 0>>` is `q` then U+0000), so
        # String.valid?/1 alone cannot reject it — the NUL byte is what discriminates,
        # and RFC 4180 TEXTDATA excludes it from a CSV either way.
        String.contains?(line, <<0>>) -> {:halt, {:error, @nul_byte_error}}
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

  @doc """
  Rewrite the file at `path` without its leading BOM.

  Needed when the uploaded file is forwarded verbatim to another service:
  stripping the BOM only from our own stream would validate one view of the
  file and upload another.
  """
  @spec strip_bom_from_file(Path.t()) :: :ok | {:error, File.posix()}
  def strip_bom_from_file(path) do
    case File.read(path) do
      {:ok, @bom <> rest} -> File.write(path, rest)
      {:ok, _contents} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec invalid_byte_error(pos_integer()) :: String.t()
  defp invalid_byte_error(row) do
    "Line #{row} of the file is not valid UTF-8. This usually means a smart quote, " <>
      "apostrophe, dash or accented letter was saved in a Windows encoding. " <> @resave_hint
  end
end
