defmodule Glific.WebChannel.ProductMetricsTest do
  # Not async: the web channel flag is global state, and Mock replaces Appsignal globally.
  use Glific.DataCase

  import Mock

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Fixtures,
    Providers.Web.Message,
    WebChannelFlagHelpers
  }

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    %{contact: Fixtures.contact_fixture()}
  end

  # The `web_channel_event_count` events recorded while `fun` runs, as {event, organization_id}.
  defp counted(fun) do
    with_mock Appsignal, [:passthrough],
      increment_counter: fn _metric, _count, _tags -> :ok end do
      fun.()

      for {_pid,
           {Appsignal, :increment_counter,
            ["web_channel_event_count", 1, %{event: event, organization_id: organization_id}]},
           _result} <- call_history(Appsignal),
          do: {event, String.to_integer(organization_id)}
    end
  end

  defp enabled(fun), do: WebChannelFlagHelpers.with_web_channel_enabled(1, fun)

  # The AppSignal counters the web provider records while `fun` runs, as {metric, tags}.
  defp provider_counted(fun) do
    with_mock Appsignal, [:passthrough],
      increment_counter: fn _metric, _count, _tags -> :ok end do
      fun.()

      for {_pid, {Appsignal, :increment_counter, [metric, 1, %{provider: "web"} = tags]}, _result} <-
            call_history(Appsignal),
          do: {metric, Map.drop(tags, [:provider, :organization_id])}
    end
  end

  describe "inbound messages" do
    test "a text message is not an upload", %{contact: contact} do
      events =
        counted(fn ->
          enabled(fn -> {:ok, _} = WebMessage.receive_message(contact, %{body: "hi"}) end)
        end)

      assert events == []
    end

    for {type, content_type} <- [
          image: "image/png",
          audio: "audio/ogg",
          video: "video/mp4",
          document: "application/pdf"
        ] do
      test "a #{type} message also counts as a completed upload", %{contact: contact} do
        url = "https://storage.googleapis.com/test-bucket/some/file"

        events =
          counted(fn ->
            enabled(fn ->
              {:ok, _} =
                WebMessage.receive_message(
                  contact,
                  %{url: url, source_url: url, content_type: unquote(content_type), body: ""},
                  unquote(type)
                )
            end)
          end)

        assert events == [{"media_upload_completed", contact.organization_id}]
      end
    end
  end

  describe "outbound messages" do
    defp outbound(contact, attrs) do
      Fixtures.message_fixture(
        Map.merge(
          %{
            sender_id: Glific.Partners.organization_contact_id(contact.organization_id),
            receiver_id: contact.id,
            contact_id: contact.id,
            flow: :outbound,
            channel: :web
          },
          attrs
        )
      )
    end

    test "a message sent by staff is counted as staff", %{contact: contact} do
      message = outbound(contact, %{})

      assert counted(fn -> enabled(fn -> {:ok, _} = Message.send_text(message) end) end) ==
               [{"message_sent_staff", contact.organization_id}]
    end

    test "a message sent by a flow is counted as flow", %{contact: contact} do
      message = outbound(contact, %{flow_id: 1})

      assert counted(fn -> enabled(fn -> {:ok, _} = Message.send_text(message) end) end) ==
               [{"message_sent_flow", contact.organization_id}]
    end
  end

  describe "web opt-in" do
    test "is counted once, when it is first recorded" do
      username = "learner_#{System.unique_integer([:positive])}"

      events =
        counted(fn ->
          enabled(fn ->
            for _ <- 1..2 do
              {:ok, _} =
                Contacts.contact_opted_in(:web, username, %{organization_id: 1}, method: "NGO")
            end
          end)
        end)

      assert events == [{"opt_in_recorded", 1}]
    end

    test "a WhatsApp opt-in is not counted", %{contact: contact} do
      events =
        counted(fn ->
          enabled(fn ->
            {:ok, _} =
              Contacts.contact_opted_in(:whatsapp, contact.phone, %{organization_id: 1},
                method: "URL"
              )
          end)
        end)

      assert events == []
    end
  end

  describe "AppSignal provider counters" do
    test "an inbound message is received under the web provider", %{contact: contact} do
      counters =
        provider_counted(fn ->
          enabled(fn -> {:ok, _} = WebMessage.receive_message(contact, %{body: "hi"}) end)
        end)

      assert counters == [{"provider_receive_count", %{type: "text"}}]
    end

    test "a delivered outbound message is a successful send", %{contact: contact} do
      message = outbound(contact, %{})

      counters =
        provider_counted(fn -> enabled(fn -> {:ok, _} = Message.send_text(message) end) end)

      assert counters == [{"provider_send_count", %{status: "success", type: "session"}}]
    end

    test "an outbound message that cannot be marked sent is a failed send", %{contact: contact} do
      message = outbound(contact, %{})
      changeset = Ecto.Changeset.add_error(Ecto.Changeset.change(message), :status, "is invalid")

      counters =
        provider_counted(fn ->
          with_mock Glific.Messages, [:passthrough],
            update_message: fn _message, _attrs -> {:error, changeset} end do
            enabled(fn -> {:error, _} = Message.send_text(message) end)
          end
        end)

      assert counters == [{"provider_send_count", %{status: "error", type: "session"}}]
    end
  end
end
