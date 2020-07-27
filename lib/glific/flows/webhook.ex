defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  @doc """
  Build a tesla dynamic client based on arguments in the flow
  """
  @spec client(String.t()) :: Tesla.Client.t()
  def client(url) do
    middleware = [
      {Tesla.Middleware.BaseUrl, url},
      Tesla.Middleware.JSON,
    ]

    Tesla.client(middleware)
  end

  @doc """
  Send a get request, and if success, sned the json map back
  """
  @spec get(Tesla.Client.t(), String.t(), map(), String.t() | nil) :: map() | nil
  def get(client, url, headers, body) do
    case Tesla.get(url, headers: headers, body: body) do
      {:ok, json} -> json
      {:error, _} -> nil
    end
  end
end
