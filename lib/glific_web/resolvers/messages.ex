defmodule GlificWeb.Resolvers.Messages do
  @moduledoc """
  Message Resolver which sits between the GraphQL schema and Glific Message Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Repo
  }

  alias GlificWeb.Resolvers.Helper

  @doc """
  Get a specific message by id
  """
  @spec message(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def message(_, %{id: id}, _) do
    with {:ok, message} <- Repo.fetch(Message, id),
         do: {:ok, %{message: message}}
  end

  @doc """
  Get the list of messages filtered by args
  """
  @spec messages(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def messages(_, args, context) do
    {:ok, Messages.list_messages(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of messages filtered by args
  """
  @spec count_messages(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_messages(_, args, context) do
    {:ok, Messages.count_messages(Helper.add_org_filter(args, context))}
  end

  @doc false
  @spec create_message(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_message(_, %{input: params}, _) do
    with {:ok, message} <- Messages.create_message(params) do
      {:ok, %{message: message}}
    end
  end

  @doc false
  @spec update_message(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_message(_, %{id: id, input: params}, _) do
    with {:ok, message} <- Repo.fetch(Message, id),
         {:ok, message} <- Messages.update_message(message, params) do
      {:ok, %{message: message}}
    end
  end

  @doc false
  @spec delete_message(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_message(_, %{id: id}, _) do
    with {:ok, message} <- Repo.fetch(Message, id),
         {:ok, message} <- Messages.delete_message(message) do
      {:ok, message}
    end
  end

  @doc false
  @spec create_and_send_message(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, %{message: Message.t()}}
  def create_and_send_message(_, %{input: params}, _) do
    with {:ok, message} <- Messages.create_and_send_message(params),
         do: {:ok, %{message: message}}
  end

  @doc false
  @spec create_and_send_message_to_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_and_send_message_to_contacts(_, %{input: message, contact_ids: contact_ids}, _) do
    with {:ok, messages} <- Messages.create_and_send_message_to_contacts(message, contact_ids),
         do: {:ok, messages}
  end

  @doc false
  @spec send_hsm_message(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def send_hsm_message(_, %{template_id: id, receiver_id: receiver_id, parameters: parameters}, _) do
    with {:ok, message} <- Messages.create_and_send_hsm_message(id, receiver_id, parameters),
         do: {:ok, %{message: message}}
  end

  # Message Media Resolver which sits between the GraphQL schema and Glific
  # Message Context API.
  # This layer basically stiches together
  # one or more calls to resolve the incoming queries.

  @doc """
  Get a specific message media by id
  """
  @spec message_media(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def message_media(_, %{id: id}, _) do
    with {:ok, message_media} <- Repo.fetch(MessageMedia, id),
         do: {:ok, %{message_media: message_media}}
  end

  @doc false
  @spec messages_media(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def messages_media(_, args, _) do
    {:ok, Messages.list_messages_media(args)}
  end

  @doc """
  Get the count of message media
  """
  @spec count_messages_media(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_messages_media(_, args, _) do
    {:ok, Messages.count_messages_media(args)}
  end

  @doc false
  @spec create_message_media(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_message_media(_, %{input: params}, _) do
    with {:ok, message_media} <- Messages.create_message_media(params) do
      {:ok, %{message_media: message_media}}
    end
  end

  @doc false
  @spec update_message_media(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_message_media(_, %{id: id, input: params}, _) do
    with {:ok, message_media} <- Repo.fetch(MessageMedia, id),
         {:ok, message_media} <- Messages.update_message_media(message_media, params) do
      {:ok, %{message_media: message_media}}
    end
  end

  @doc false
  @spec delete_message_media(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_message_media(_, %{id: id}, _) do
    with {:ok, message_media} <- Repo.fetch(MessageMedia, id),
         {:ok, message_media} <- Messages.delete_message_media(message_media) do
      {:ok, message_media}
    end
  end

  ## Subcriptions

  @doc false
  @spec publish_sent_message(map(), any(), any()) ::
          {:ok, Message.t()} | {:error, any}
  def publish_sent_message(args, _, _) do
    case args do
      %{message: message} -> {:ok, message}
      message -> {:ok, message}
    end
  end
end
