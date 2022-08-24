defmodule Glific.MessageConversations do
  @moduledoc """
  The Messages Conversations context.
  """

  require Logger

  alias Glific.{
    Messages.Message,
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

  @doc """
  Handles incoming billing event
  """
  @spec receive_billing_event(map(), non_neg_integer()) :: any()
  def receive_billing_event(params, organization_id) do
    references = get_in(params, ["payload", "references"])
    deductions = get_in(params, ["payload", "deductions"])
    bsp_message_id = references["gsId"] || references["id"]
    phone = references["destination"]

    Repo.fetch_by(Message, %{
      bsp_message_id: bsp_message_id,
      organization_id: organization_id
    })
    |> case do
      {:ok, message} ->
        %{
          deduction_type: deductions["type"],
          is_billable: deductions["billable"],
          conversation_id: references["conversationId"],
          payload: params,
          message_id: message.id,
          organization_id: organization_id
        }
        |> create_message_conversation()

      _ ->
        Logger.error(
          "Could not find message with id: #{bsp_message_id} and phone #{phone} for org_id: #{organization_id}"
        )
    end
  end
end
