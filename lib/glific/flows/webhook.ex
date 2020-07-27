defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  @doc """
  Build a tesla dynamic client based on arguments in the flow
  @spec client(String.t()) :: Tesla.Client.t()
  def client(url) do
    middleware = [
      {Tesla.Middleware.BaseUrl, url},
      Tesla.Middleware.JSON
    ]

    Tesla.client(middleware)
  end

  Send a get request, and if success, sned the json map back
  """
  @spec get(String.t(), map(), String.t() | nil) :: map() | nil
  def get(url, headers, body) do
    case Tesla.get(url, headers: headers, body: body) do
      {:ok, %Tesla.Env{status: 200} = message} ->
        message.body |> Jason.decode!() |> get_in(["results", Access.at(0)])
      _ -> nil
    end
  end
end
