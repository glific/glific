defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.

  > #### Deprecated {: .warning}
  >
  > This module is a thin, deprecated router. External-call webhook nodes now live under
  > `Glific.Flows.Webhooks.*` and are invoked through `Glific.Flows.Webhooks.Dispatcher`, which
  > owns failure reporting and latency telemetry. Each clause below either delegates to the
  > dispatcher or is a pure-local helper (no external call, no error reporting). Do not add new
  > webhook logic here — add a `Glific.Flows.Webhooks` implementation module and register it in
  > `Glific.Flows.Webhooks.Registry` instead.
  """

  alias Glific.Flows.Webhooks.Dispatcher

  @doc """
  Create a webhook with different signatures along with header, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map(), list()) :: map() | String.t()
  def webhook(function, fields, _headers), do: webhook(function, fields)

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: any()
  def webhook("parse_via_chat_gpt", fields),
    do: Dispatcher.dispatch("parse_via_chat_gpt", fields)

  def webhook("parse_via_gpt_vision", fields),
    do: Dispatcher.dispatch("parse_via_gpt_vision", fields)

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

  def webhook("geolocation", fields),
    do: Dispatcher.dispatch("geolocation", fields)

  def webhook("send_wa_group_poll", fields),
    do: Dispatcher.dispatch("send_wa_group_poll", fields)

  def webhook("create_certificate", fields),
    do: Dispatcher.dispatch("create_certificate", fields)

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}
end
