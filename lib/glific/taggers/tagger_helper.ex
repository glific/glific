defmodule Glific.Taggers.TaggerHelper do
  @moduledoc """
  Helper functions for tagging incoming messages
  """

  import Ecto.Query

  alias Glific.{
    Messages.Message,
    Repo,
    Tags,
    Tags.Tag
  }

  @doc """
  Helper function to add tags to inbound message
  """
  @spec tag_inbound_message({:ok, Message.t()}) :: {:ok, Message.t()}
  def tag_inbound_message({:ok, message}) do
    message
    |> add_unread_tag()
    |> add_not_replied_tag()
    |> remove_not_responded_tag()

    {:ok, message}
  end

  @spec add_tag(Message.t(), String.t()) :: Message.t()
  defp add_tag(message, tag_label) do
    {:ok, tag} = Repo.fetch_by(Tag, %{label: tag_label})

    {:ok, _} =
      Tags.create_message_tag(%{
        message_id: message.id,
        tag_id: tag.id
      })

    message
  end

  @spec add_unread_tag(Message.t()) :: Message.t()
  defp add_unread_tag(message) do
    add_tag(message, "Unread")
  end

  @spec add_not_replied_tag(Message.t()) :: Message.t()
  defp add_not_replied_tag(message) do
    Tags.remove_tag_from_all_message(message.contact_id, "Not Replied")
    add_tag(message, "Not Replied")
  end

  @spec remove_not_responded_tag(Message.t()) :: Message.t()
  defp remove_not_responded_tag(message) do
    # Remove "Not Responded" tag from last outbound message
    {:ok, tag} = Repo.fetch_by(Glific.Tags.Tag, %{label: "Not Responded"})

    # To fix: don't remove tag if message is not yet delivered
    with last_outbound_message when last_outbound_message != nil <-
           Message
           |> where([m], m.receiver_id == ^message.contact_id)
           |> where([m], m.flow == "outbound")
           |> where([m], m.status == "sent")
           |> Ecto.Query.last()
           |> Repo.one(),
         message_tag when message_tag != nil <-
           Glific.Tags.MessageTag
           |> where([mt], mt.tag_id == ^tag.id)
           |> where([mt], mt.message_id == ^last_outbound_message.id)
           |> Ecto.Query.last()
           |> Repo.one(),
         do: Glific.Tags.delete_message_tag(message_tag)
  end

  @spec tag_outbound_message(Message.t()) :: :ok
  def tag_outbound_message(message) do
    # Add "Not Responded" tag to message
    {:ok, tag} = Repo.fetch_by(Glific.Tags.Tag, %{label: "Not Responded"})

    {:ok, _} =
      Glific.Tags.create_message_tag(%{
        message_id: message.id,
        tag_id: tag.id
      })

    # Remove not responded tag from last outbound message if any
    # don't remove tag if message is not yet delivered
    with last_outbound_message when last_outbound_message != nil <-
           Message
           |> where([m], m.id != ^message.id)
           |> where([m], m.receiver_id == ^message.receiver_id)
           |> where([m], m.flow == "outbound")
           |> where([m], m.status == "sent")
           |> Ecto.Query.last()
           |> Repo.one(),
         message_tag when message_tag != nil <-
           Glific.Tags.MessageTag
           |> where([m], m.tag_id == ^tag.id)
           |> where([m], m.message_id == ^last_outbound_message.id)
           |> Ecto.Query.last()
           |> Repo.one(),
         do: Glific.Tags.delete_message_tag(message_tag)

    :ok
  end
end
