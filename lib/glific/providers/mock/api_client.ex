defmodule Glific.Providers.Mock.ApiClient do
  @moduledoc """
  Http API client to intract with Mock
  """
  use Tesla
  # plug Tesla.Middleware.BaseUrl, Application.fetch_env!(:glific, :provider_url)
  # plug Tesla.Middleware.Logger, log_level: :debug

  # Tesla.Mock.mock(fn
  # %{method: :post} ->
  #   %Tesla.Env{status: 200, body: "hello"}
  # end)

    def mock(_url, _payload) do
     response = %Tesla.Env{status: 200, body: Jason.encode!(%{"status" => "submitted", "messageId" => "ee4a68a0-1203-4c85-8dc3-49d0b3226a35"})}
     {:ok, response}
    end
end
