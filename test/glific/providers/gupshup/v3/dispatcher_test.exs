defmodule Glific.Providers.Gupshup.V3.DispatcherTest do
  use Glific.DataCase

  import ExUnit.CaptureLog

  alias Glific.Providers.Gupshup.V3.Dispatcher
  alias Glific.Providers.Gupshup.V3.Handlers.FormResponse

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  test "logs an interactive message type with no handler", %{organization_id: organization_id} do
    value = %{
      "messages" => [%{"type" => "interactive", "interactive" => %{"type" => "button_reply"}}]
    }

    log =
      capture_log(fn -> "messages" |> entries(value) |> Dispatcher.dispatch(organization_id) end)

    assert log =~ "Unhandled Gupshup V3 callback change: field=messages, type=button_reply"
  end

  test "logs a message type with no handler", %{organization_id: organization_id} do
    value = %{"messages" => [%{"type" => "text", "text" => %{"body" => "Hi"}}]}

    log =
      capture_log(fn -> "messages" |> entries(value) |> Dispatcher.dispatch(organization_id) end)

    assert log =~ "Unhandled Gupshup V3 callback change: field=messages, type=text"
  end

  test "logs a change field with no handler", %{organization_id: organization_id} do
    value = %{"event" => "APPROVED"}

    log =
      capture_log(fn ->
        "message_template_status_update"
        |> entries(value)
        |> Dispatcher.dispatch(organization_id)
      end)

    assert log =~
             "Unhandled Gupshup V3 callback change: field=message_template_status_update, type=message_template_status_update"
  end

  test "skips entries and changes that are not V3 shaped", %{organization_id: organization_id} do
    assert :ok =
             Dispatcher.dispatch(
               [%{"id" => "1"}, %{"changes" => [%{"field" => "x"}]}],
               organization_id
             )
  end

  test "form response handler ignores a value without a contact", %{
    organization_id: organization_id
  } do
    assert :ok =
             FormResponse.handle(%{"messages" => [%{"type" => "interactive"}]}, organization_id)
  end

  defp entries(field, value), do: [%{"changes" => [%{"field" => field, "value" => value}]}]
end
