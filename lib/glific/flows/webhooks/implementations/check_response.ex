defmodule Glific.Flows.Webhooks.CheckResponse do
  @moduledoc """
  Compare a contact's response against the expected answer (`check_response` node). Pure-local.
  """

  use Glific.Flows.Webhooks.Sync, name: "check_response"

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) :: {:ok, map()}
  def call(fields, _ctx) do
    {:ok, %{response: String.equivalent?(fields["correct_response"], fields["user_response"])}}
  end
end
