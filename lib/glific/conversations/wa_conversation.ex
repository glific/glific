defmodule Glific.Conversations.WAConversation do
  @moduledoc """
  The Glific Abstraction to represent the conversation with a wa group. This unifies a vast majority of the
  glific data types including: wa_message, contact
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    WAGroup,
    WAGroup.WAMessage
  }

  @type t() :: %__MODULE__{
          wa_group: WAGroup.t(),
          wa_messages: [WAMessage.t()]
        }

  # structure to hold a contact and the conversations with the wa_group
  # the messages should be in descending order, i.e. most recent ones first
  embedded_schema do
    embeds_one(:wa_group, WAGroup)
    embeds_many(:wa_messages, WAMessage)
  end

  @doc """
  Create a new conversation.
  """
  @spec new(WAGroup.t() | nil, [WAMessage.t()]) :: WAConversation.t()
  def new(wa_group, wa_messages \\ []) do
    %WAConversation{wa_group: wa_group, wa_messages: wa_messages}
  end
end
