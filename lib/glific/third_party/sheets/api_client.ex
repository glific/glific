defmodule Glific.Sheets.ApiClient do
  @moduledoc """
  Http API client to interact with Gupshup
  """

  @doc """
  Get the CSV content from the url.
  """
  @spec get_csv_content(Keyword.t()) :: Keyword.t()
  def get_csv_content([url: url] = _opts) do
    {:ok, response} =
      get_tesla_middlewares()
      |> Tesla.client()
      |> Tesla.get(url)

    {:ok, stream} = StringIO.open(response.body)

    IO.binstream(stream, :line)
    |> CSV.decode(headers: true, field_transform: &String.trim/1, escape_max_lines: 50)
  end

  def get_csv_content(_opts), do: [ok: %{}]

  @spec get_tesla_middlewares :: list()
  defp get_tesla_middlewares do
    [
      Tesla.Middleware.FollowRedirects,
      {Tesla.Middleware.Telemetry, metadata: %{provider: "google_sheets", sampling_scale: 10}}
    ] ++
      Glific.get_tesla_retry_middleware()
  end
end
