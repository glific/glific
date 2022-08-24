defmodule Glific.MessageConversations do
  @moduledoc """
  The Messages Conversations context.
  """

  require Logger

  alias Glific.{
    Messages.MessageConversation,
    Repo
  }

  @doc """
  Gets a single message conversation

  Raises `Ecto.NoResultsError` if the Message does not exist.

  ## Examples

      iex> get_message_conversation!(123)
      %Message{}

      iex> get_message_conversation!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message_conversation!(integer) :: MessageConversation.t()
  def get_message_conversation!(id), do: Repo.get!(MessageConversation, id)

  @doc """
  Creates a message conversation

  ## Examples

      iex> create_message_conversation(%{field: value})
      {:ok, %MessageConversation{}}

      iex> create_message_conversation(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message_conversation(map()) ::
          {:ok, MessageConversation.t()} | {:error, Ecto.Changeset.t()}
  def create_message_conversation(attrs) do
    %MessageConversation{}
    |> MessageConversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a message conversation.

  ## Examples

      iex> update_message_conversation(message_conversation, %{field: new_value})
      {:ok, %MessageConversation{}}

      iex> update_message_conversation(message_conversation, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message_conversation(MessageConversation.t(), map()) ::
          {:ok, MessageConversation.t()} | {:error, Ecto.Changeset.t()}
  def update_message_conversation(%MessageConversation{} = message_conversation, attrs) do
    message_conversation
    |> MessageConversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message conversation.

  ## Examples

      iex> delete_message_conversation(message)
      {:ok, %MessageConversation{}}

      iex> delete_message_conversation(message)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message_conversation(MessageConversation.t()) ::
          {:ok, MessageConversation.t()} | {:error, Ecto.Changeset.t()}
  def delete_message_conversation(%MessageConversation{} = message_conversation) do
    Repo.delete(message_conversation)
  end
end
