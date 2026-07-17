defmodule Glific.Flows.Webhooks.GetButtons do
  @moduledoc """
  Split a `|`-delimited string into numbered quick-reply buttons (`get_buttons` node). Pure-local.
  """

  use Glific.Flows.Webhooks.Sync, name: "get_buttons"

  alias Glific.Flows.Webhooks.ErrorType

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def call(%{"buttons_data" => buttons_data}, _ctx) when is_binary(buttons_data) do
    buttons =
      buttons_data
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

  def call(_fields, _ctx) do
    {:error, :empty_input, "get_buttons requires buttons_data as a `|`-delimited string"}
  end
end
