defmodule Glific.Flows.Webhooks.GetButtons do
  @moduledoc """
  Split a `|`-delimited string into numbered quick-reply buttons (`get_buttons` node). Pure-local.
  """

  use Glific.Flows.Webhooks.Sync, name: "get_buttons"

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) :: {:ok, map()}
  def call(fields, _ctx) do
    buttons =
      fields["buttons_data"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    {:ok,
     %{
       buttons: buttons,
       button_count: length(Map.keys(buttons)),
       is_valid: true
     }}
  end
end
