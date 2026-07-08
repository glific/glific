defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.

  > #### Deprecated {: .warning}
  >
  > This module is a thin, deprecated fallback. External-call webhook nodes now live under
  > `Glific.Flows.Webhooks.*` and are routed by `Glific.Flows.Webhook.dispatch_function/3`
  > straight to `Glific.Flows.Webhooks.Dispatcher` via `Glific.Flows.Webhooks.Registry` — they
  > intentionally have **no** clause here (see `geolocation`, `filesearch-gpt`, `speech_to_text`,
  > `parse_via_chat_gpt`, `create_certificate`, …). A registered webhook never reaches this
  > module.
  >
  > Only the two pure-local clauses (`get_buttons`, `check_response` — no external call, no error
  > reporting) and the missing-implementation fallthrough remain. Do not add new webhook logic
  > here; add a `Glific.Flows.Webhooks` implementation module and register it in the `Registry`.
  """

  @doc """
  Route a webhook function by name. Only the pure-local clauses (`get_buttons`,
  `check_response`) and the missing-implementation fallthrough remain; every external-call
  node is handled by `Glific.Flows.Webhooks.Dispatcher` and never reaches this module.
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("get_buttons", fields) do
    buttons =
      fields["buttons_data"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields),
    do: %{response: String.equivalent?(fields["correct_response"], fields["user_response"])}

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}
end
