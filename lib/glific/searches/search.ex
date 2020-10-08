defmodule Glific.Searches.Search do
  @moduledoc """
  The Glific Abstraction to represent the conversation with a user. This unifies a vast majority of the
  glific data types including: message, contact, and tag
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{Contacts.Contact, Messages.Message, Searches.SearchItem}

  @type t() :: %__MODULE__{
          contacts: [SearchItem.t()],
          messages: [SearchItem.t()],
          tags: [SearchItem.t()]
        }

  # structure to hold a contact and the conversations with the contact
  # the messages should be in descending order, i.e. most recent ones first
  embedded_schema do
    embeds_many(:contacts, SearchItem)
    embeds_many(:messages, SearchItem)
    embeds_many(:tags, SearchItem)
  end

  @doc """
  Create a new conversation. A contact is required for the conversation. Messages can
  be added later on
  """
  @spec new(Contact.t(), [Message.t()]) :: Conversation.t()
  def new(contacts, messages, tags) do
    %Search{contacts: contacts, messages: messages, tags: tags}
  end
end
