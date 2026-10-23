defmodule Glific.CSV.Encoding do
  @moduledoc """
  Rejects CSV uploads that are not valid UTF-8 and strips the Excel BOM.
  """

  @bom <<0xEF, 0xBB, 0xBF>>

  @resave_hint "Re-save it as UTF-8 (Excel: Save As → CSV UTF-8; Google Sheets: Download → CSV)."

  @nul_byte_error "The file is UTF-16 or UTF-32, not UTF-8. " <> @resave_hint

  @doc "Check a CSV is valid UTF-8, given its raw contents or a stream of one line per element."
  @spec validate(binary() | Enumerable.t()) :: :ok | {:error, String.t()}
  # splitter, not split: a 20MB upload split eagerly measured at >100MB of heap
  def validate(contents) when is_binary(contents),
    do: contents |> String.splitter("\n") |> validate()

  def validate(lines) do
    lines
    |> Stream.with_index(1)
    |> Enum.reduce_while(:ok, fn {line, row}, _acc ->
      cond do
        # UTF-16 of ASCII passes String.valid?/1 (`<<113, 0>>` is `q` then U+0000), so NUL
        # bytes are the only way to catch it
        String.contains?(line, <<0>>) -> {:halt, {:error, @nul_byte_error}}
        String.valid?(line) -> {:cont, :ok}
        true -> {:halt, {:error, invalid_byte_error(row)}}
      end
    end)
  end

  @doc "Strip the byte order mark from the first line of a stream."
  @spec strip_bom(Enumerable.t()) :: Enumerable.t()
  def strip_bom(lines) do
    lines
    |> Stream.with_index()
    |> Stream.map(fn
      {line, 0} -> String.replace_prefix(line, @bom, "")
      {line, _row} -> line
    end)
  end

  @doc "Rewrite the file at `path` without its byte order mark."
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
    "Line #{row} is not valid UTF-8 (a smart quote, dash or accent saved in a Windows encoding). " <>
      @resave_hint
  end
end
