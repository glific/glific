defmodule Glific.Providers.Gupshup.V3.DispatcherTest do
  use Glific.DataCase

  import Mock

  alias Glific.Providers.Gupshup.V3.Dispatcher
  alias Glific.Providers.Gupshup.V3.Handlers.FormResponse
  alias Glific.Providers.Gupshup.V3.Handlers.Status

  @status_value %{"statuses" => [%{"gs_id" => "gupshup-id", "status" => "read"}]}

  @form_response_value %{
    "contacts" => [%{"profile" => %{"name" => "Smit"}, "wa_id" => "919917443994"}],
    "messages" => [%{"type" => "interactive", "interactive" => %{"type" => "nfm_reply"}}]
  }

  test "passes a statuses change to the status handler", %{organization_id: organization_id} do
    with_mocks([
      {Status, [], handle: fn _value, _organization_id -> :ok end},
      {FormResponse, [], handle: fn _value, _organization_id -> :ok end}
    ]) do
      assert :ok = "messages" |> entries(@status_value) |> Dispatcher.dispatch(organization_id)

      assert_called(Status.handle(@status_value, organization_id))
      assert_not_called(FormResponse.handle(:_, :_))
    end
  end

  test "passes an nfm_reply change to the form response handler",
       %{organization_id: organization_id} do
    with_mocks([
      {Status, [], handle: fn _value, _organization_id -> :ok end},
      {FormResponse, [], handle: fn _value, _organization_id -> :ok end}
    ]) do
      assert :ok =
               "messages" |> entries(@form_response_value) |> Dispatcher.dispatch(organization_id)

      assert_called(FormResponse.handle(@form_response_value, organization_id))
      assert_not_called(Status.handle(:_, :_))
    end
  end

  test "passes each change in a callback to its own handler", %{organization_id: organization_id} do
    entries = [
      %{
        "changes" => [
          %{"field" => "messages", "value" => @status_value},
          %{"field" => "messages", "value" => @form_response_value}
        ]
      }
    ]

    with_mocks([
      {Status, [], handle: fn _value, _organization_id -> :ok end},
      {FormResponse, [], handle: fn _value, _organization_id -> :ok end}
    ]) do
      assert :ok = Dispatcher.dispatch(entries, organization_id)

      assert_called(Status.handle(@status_value, organization_id))
      assert_called(FormResponse.handle(@form_response_value, organization_id))
    end
  end

  test "ignores an interactive message type with no handler", %{organization_id: organization_id} do
    value = %{
      "messages" => [%{"type" => "interactive", "interactive" => %{"type" => "button_reply"}}]
    }

    assert :ok = "messages" |> entries(value) |> Dispatcher.dispatch(organization_id)
  end

  test "ignores a message type with no handler", %{organization_id: organization_id} do
    value = %{"messages" => [%{"type" => "text", "text" => %{"body" => "Hi"}}]}

    assert :ok = "messages" |> entries(value) |> Dispatcher.dispatch(organization_id)
  end

  test "ignores a change field with no handler", %{organization_id: organization_id} do
    value = %{"event" => "APPROVED"}

    assert :ok =
             "message_template_status_update"
             |> entries(value)
             |> Dispatcher.dispatch(organization_id)
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
