defmodule Glific.CSV.Encoding do
  @moduledoc """
  Rejects CSV uploads that are not valid UTF-8 and strips the Excel BOM.
  """

  @bom "﻿"

  @resave_hint "Re-save it as UTF-8 (Excel: Save As, CSV UTF-8; Google Sheets: Download, CSV)."

  @nul_byte_error "The file is UTF-16 or UTF-32, not UTF-8. " <> @resave_hint

  @doc "Open exactly one of `file_path:`, `url:` or `data:` as a UTF-8-checked, BOM-free line stream."
  @spec stream(Keyword.t()) :: {:ok, Enumerable.t()} | {:error, String.t()}
  def stream(opts), do: opts |> Keyword.take([:file_path, :url, :data]) |> open()

  @doc "Check a CSV is valid UTF-8, given its raw contents or a stream of one line per element."
  @spec validate(binary() | Enumerable.t()) :: :ok | {:error, String.t()}
  # splitter, not split, so a large upload is never held in memory twice
  def validate(contents) when is_binary(contents),
    do: contents |> String.splitter("\n") |> validate()

  def validate(lines) do
    lines
    |> Stream.with_index(1)
    |> Enum.reduce_while(:ok, fn {line, row}, _acc ->
      cond do
        # UTF-16 of ASCII passes String.valid?/1 (`<<113, 0>>` is `q` then U+0000), so NUL
        # bytes are the only way to catch it
        String.contains?(line, <<0>>) ->
          {:halt, {:error, @nul_byte_error}}

        String.valid?(line) ->
          {:cont, :ok}

        true ->
          {:halt,
           {:error,
            "Line #{row} is not valid UTF-8 (a smart quote, dash or accent saved in a Windows encoding). " <>
              @resave_hint}}
      end
    end)
  end

  @doc "Strip the byte order mark from the start of each line."
  @spec strip_bom(Enumerable.t()) :: Enumerable.t()
  def strip_bom(lines), do: Stream.map(lines, &String.replace_prefix(&1, @bom, ""))

  @spec open(Keyword.t()) :: {:ok, Enumerable.t()} | {:error, String.t()}
  defp open(file_path: path) do
    stream = path |> Path.expand() |> File.stream!()
    with :ok <- validate(stream), do: {:ok, strip_bom(stream)}
  rescue
    File.Error -> {:error, "Could not read the CSV file."}
  end

  defp open(data: data) when is_binary(data) do
    with :ok <- validate(data) do
      {:ok, pid} = StringIO.open(data)
      {:ok, pid |> IO.binstream(:line) |> strip_bom()}
    end
  end

  # A non-200 body is an error page, not contacts, so it is never parsed as CSV.
  defp open(url: url) do
    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} -> open(data: body)
      _ -> {:error, "Could not download the CSV from the given URL."}
    end
  end

  defp open(_), do: {:error, "Please specify exactly one of: file_path, url or data"}
end
