defmodule Glific.Sheets.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """

  # @gupshup_url "https://ecc1b36b412e0e08549aefec29aa4bf7.m.pipedream.net"

  use Tesla

  plug Tesla.Middleware.FollowRedirects

  @doc """
  Get the CSV content from the url.
  """
  @spec get_csv_content(Keyword.t()) :: Keyword.t()
  def get_csv_content([url: url] = _opts) do
    {:ok, response} = get(url)
    {:ok, stream} = StringIO.open(response.body)

    IO.binstream(stream, :line)
    |> CSV.decode(headers: true, strip_fields: true)
  end

  def get_csv_content(_opts), do: [ok: %{}]
end
