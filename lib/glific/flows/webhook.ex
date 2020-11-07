defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  @doc """
  Execute a webhook action, could be either get or post for now
  """
  @spec execute(Action.t(), FlowContext.t()) :: map() | nil
  def execute(action, context) do
    headers = Keyword.new(
      action.headers,
      fn {k, v} -> {String.to_existing_atom(k), v} end
    )
    if acrion.method == "get" do
      get(action.url, headers, action.body)
    else
      post(action.url, headers, action.body)
    end
  end

  @doc """
  Send a get request, and if success, sned the json map back
  """
  @spec get(String.t(), Keyword.t(), String.t() | nil) :: map() | nil
  def get(url, headers, body) do
    case Tesla.get(url, headers: headers, body: body) do
      {:ok, %Tesla.Env{status: 200} = message} ->
        message.body |> Jason.decode!() |> get_in(["results", Access.at(0)])

      _ ->
        nil
    end
  end
end
