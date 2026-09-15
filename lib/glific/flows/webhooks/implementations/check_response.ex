defmodule Glific.Flows.Webhooks.CheckResponse do
  @moduledoc """
  Compare a contact's response against the expected answer (`check_response` node). Pure-local.
  """

  use Glific.Flows.Webhooks.Sync, name: "check_response"

  alias Glific.Flows.Webhooks.ErrorType

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def call(%{"correct_response" => correct, "user_response" => user}, _ctx)
      when is_binary(correct) and is_binary(user) do
    {:ok, %{response: String.equivalent?(correct, user)}}
  end

  def call(_fields, _ctx) do
    {:error, :empty_input, "check_response requires correct_response and user_response as text"}
  end
end
