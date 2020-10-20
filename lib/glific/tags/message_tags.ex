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
          message_tags: [MessageTag.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of tags we deleted
    field :number_deleted, :integer, default: 0
    embeds_many(:message_tags, MessageTag)
  end

  @doc """
  Creates and/or deletes a list of message tags, each tag attached to the same message
  """
  @spec update_message_tags(map()) :: MessageTags.t()
  def update_message_tags(
        %{
          message_id: message_id,
          organization_id: organization_id,
          add_tag_ids: add_ids,
          delete_tag_ids: delete_ids
        } = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    message_tags =
      Enum.reduce(
        add_ids,
        [],
        fn tag_id, acc ->
          case Tags.create_message_tag(Map.put(attrs, :tag_id, tag_id)) do
            {:ok, message_tag} -> [message_tag | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Tags.delete_message_tag_by_ids(message_id, delete_ids, organization_id)

    %MessageTags{
      number_deleted: number_deleted,
      message_tags: message_tags
    }
  end
end
