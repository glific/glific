defmodule Glific.Conversations.Conversation do
  @moduledoc """
  The Glific Abstraction to represent the conversation with a user. This unifies a vast majority of the
  glific data types including: message, contact, and tag
  """
  alias __MODULE__

  alias Glific.{Contacts.Contact, Messages.Message}

  @type t() :: %__MODULE__{
          contact: Contact.t(),
          messages: [Message.t()]
        }

  # structure to hold a contact and the conversations with the contact
  # the messages should be in descending order, i.e. most recent ones first
  @enforce_keys [:contact]
  defstruct(
    contact: nil,
    messages: nil
  )

  @doc """
  Create a new conversation. A contact is required for the conversation. Messages can
  be added later on
  """
  @spec new(Contact.t(), [Message.t()]) :: Conversation.t()
  def new(contact, messages \\ []) do
    %Conversation{contact: contact, messages: messages}
  end

  @doc """
  Add a message to an exisiting conversation. We always add messages to the
  beginning of the message list (for efficiency), and ae assume we are adding
  messages as they come in
  """
  @spec add_message(Conversation.t(), Message.t()) :: Conversation.t()
  def add_message(conversation, message) do
    %Conversation{contact: conversation.contact, messages: [message | conversation.messages]}
  end
end
