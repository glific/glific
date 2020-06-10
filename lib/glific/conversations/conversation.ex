defmodule Glific.Conversations.Conversation do
  @moduledoc """
  The Glific Abstraction to represent the conversation with a user. This unifies a vast majority of the
  glific data types including: message, contact, and tag
  """

  @enforce_keys [:contact]
  defstruct(
    contact: nil,
    messages: nil
  )

  def new(contact, messages \ []) do
    %Conversation{contact: contact, messages: messages}
  end

end
