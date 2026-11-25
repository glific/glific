defmodule Glific.WebChannel.ProductMetricsTest do
  # Not async: the web channel flag is global state, and Mock replaces Glific.Metrics globally.
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

  # The web channel counters bumped while `fun` runs, as {name, organization_id}.
  defp counted(fun) do
    with_mock Glific.Metrics, [:passthrough], increment: fn _event, _organization_id -> :ok end do
      fun.()

      for {_pid, {Glific.Metrics, :increment, [event, organization_id]}, _result} <-
            call_history(Glific.Metrics),
          String.starts_with?(event, "Web "),
          do: {event, organization_id}
    end
  end

  defp enabled(fun), do: WebChannelFlagHelpers.with_web_channel_enabled(1, fun)

  describe "inbound messages" do
    test "a text message is counted by its type", %{contact: contact} do
      events =
        counted(fn ->
          enabled(fn -> {:ok, _} = WebMessage.receive_message(contact, %{body: "hi"}) end)
        end)

      assert events == [{"Web Message Received: text", contact.organization_id}]
    end

    test "a media message also counts as a completed upload", %{contact: contact} do
      url = "https://storage.googleapis.com/test-bucket/some/image.png"

      events =
        counted(fn ->
          enabled(fn ->
            {:ok, _} =
              WebMessage.receive_message(
                contact,
                %{url: url, source_url: url, content_type: "image/png", body: ""},
                :image
              )
          end)
        end)

      assert Enum.sort(events) == [
               {"Web Media Upload Completed", contact.organization_id},
               {"Web Message Received: image", contact.organization_id}
             ]
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
               [{"Web Message Sent: Staff", contact.organization_id}]
    end

    test "a message sent by a flow is counted as flow", %{contact: contact} do
      message = outbound(contact, %{flow_id: 1})

      assert counted(fn -> enabled(fn -> {:ok, _} = Message.send_text(message) end) end) ==
               [{"Web Message Sent: Flow", contact.organization_id}]
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

      assert events == [{"Web Opt-in Recorded", 1}]
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
end
