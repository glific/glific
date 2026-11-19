defmodule GlificWeb.WebChannel.MessageSerializerTest do
  @moduledoc false
  use Glific.DataCase, async: true

  alias Glific.{Fixtures, Repo}
  alias GlificWeb.WebChannel.MessageSerializer

  describe "serialize/1" do
    test "a text message keeps its body", %{organization_id: organization_id} do
      message = Fixtures.message_fixture(%{body: "hello there", organization_id: organization_id})

      assert %{body: "hello there", media: nil} = MessageSerializer.serialize(message)
    end

    # The caption of a media message lives on the media row, not message.body, and the widget
    # renders body as the caption — so it must be surfaced there or it is silently dropped.
    test "a media message surfaces its caption as the body", %{organization_id: organization_id} do
      media =
        Fixtures.message_media_fixture(%{
          caption: "here we go again",
          organization_id: organization_id
        })

      message =
        Fixtures.message_fixture(%{
          type: :image,
          body: "",
          media_id: media.id,
          organization_id: organization_id
        })
        |> Repo.preload(:media)

      serialized = MessageSerializer.serialize(message)

      assert serialized.body == "here we go again"
      assert serialized.media == %{url: media.url}
    end

    test "a media message with no caption serializes an empty body", %{
      organization_id: organization_id
    } do
      media = Fixtures.message_media_fixture(%{caption: "", organization_id: organization_id})

      message =
        Fixtures.message_fixture(%{
          type: :image,
          body: "",
          media_id: media.id,
          organization_id: organization_id
        })
        |> Repo.preload(:media)

      assert %{body: ""} = MessageSerializer.serialize(message)
    end
  end
end
