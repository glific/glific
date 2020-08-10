defmodule Glific.Conversations.Conversation do
  @moduledoc """
  The Glific Abstraction to represent the conversation with a user. This unifies a vast majority of the
  glific data types including: message, contact, and tag
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{Contacts.Contact, Messages.Message}

  @type t() :: %__MODULE__{
          contact: Contact.t(),
          messages: [Message.t()]
        }

  # structure to hold a contact and the conversations with the contact
  # the messages should be in descending order, i.e. most recent ones first
  embedded_schema do
    embeds_one(:contact, Contact)
    embeds_many(:messages, Message)
  end

  @doc """
  Create a new conversation. A contact is required for the conversation. Messages can
  be added later on
  """
  @spec new(Contact.t(), [Message.t()]) :: Conversation.t()
  def new(contact, messages \\ []) do
    %Conversation{contact: contact, messages: messages}
  end
end
