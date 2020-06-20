defmodule Glific.ProcessorTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Processor.Producer,
    Repo,
    Tags.MessageTag,
    Tags.Tag
  }

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  @tag :pending
  test "Lets test numeric tagging of messages" do
    number = "12"

    msg =
      Fixtures.message_fixture()
      |> Map.put(:body, number)

    # now add this to the processor queue
    Producer.add(msg)

    # assert we create a numeric tag, with a value of "12"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: "Numeric"})
    {:ok, message_tag} = Repo.fetch_by(MessageTag, %{message_id: msg.id, tag_id: tag.id})

    assert message_tag.value == number
  end
end
