defmodule Glific.Tags.MessageTags do
  @moduledoc """
  Simple container to hold all the message tags we associate with one message
  """

  alias __MODULE__

  alias Glific.{
    Tags,
    Tags.MessageTag
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          message_tags: [MessageTag.t()]
        }

  embedded_schema do
    embeds_many(:message_tags, MessageTag)
  end

  @doc """
  Creates a list of message tags, each tag attached to the same message
  """
  @spec create_message_tags(map()) :: MessageTags.t()
  def create_message_tags(attrs \\ %{}) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    message_tags =
      Enum.reduce(
        attrs[:tags_id],
        [],
        fn tag_id, acc ->
          case Tags.create_message_tag(Map.put(attrs, :tag_id, tag_id)) do
            {:ok, message_tag} -> [message_tag | acc]
            _ -> acc
          end
        end
      )

    %MessageTags{message_tags: message_tags}
  end
end
