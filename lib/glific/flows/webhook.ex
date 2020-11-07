defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  alias Glific.Flows.{
    Action,
    FlowContext
  }

  @doc """
  Execute a webhook action, could be either get or post for now
  """
  @spec execute(Action.t(), FlowContext.t()) :: map() | nil
  def execute(action, context) do
    headers =
      Keyword.new(
        action.headers,
        fn {k, v} -> {String.to_existing_atom(k), v} end
      )

    if action.method == "get" do
      get(action, headers)
    else
      post(action, context, headers)
    end
  end

  @spec post(Action.t(), FlowContext.t(), Keyword.t()) :: map() | nil
  defp post(action, context, headers) do
    {:ok, body} =
      %{
        contact: %{
          name: context.contact.name,
          phone: context.contact.phone,
          fields: context.contact.fields
        },
        results: context.results
      }
      |> Jason.encode()

    case Tesla.post(action.url, body, headers: headers) do
      {:ok, %Tesla.Env{status: 200} = message} ->
        message.body
        |> Jason.decode!()
        |> Map.get("results")

      _ ->
        nil
    end
  end

  # Send a get request, and if success, sned the json map back
  @spec get(Action.t(), Keyword.t()) :: map() | nil
  defp get(action, headers) do
    case Tesla.get(action.url, action.body, headers: headers) do
      {:ok, %Tesla.Env{status: 200} = message} ->
        message.body |> Jason.decode!() |> get_in(["results", Access.at(0)])

      _ ->
        nil
    end
  end
end
