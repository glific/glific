defmodule GlificWeb.Resolvers.Messages do
  @moduledoc """
  Message Resolver which sits between the GraphQL schema and Glific Message Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Contacts.Contact,
    Groups.Group,
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Repo,
    Users.User
  }

  @doc """
  Get a specific message by id
  """
  @spec message(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def message(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, message} <-
           Repo.fetch_by(Message, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{message: message}}
  end

  @doc """
  Get the list of messages filtered by args
  """
  @spec messages(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def messages(_, args, _) do
    {:ok, Messages.list_messages(args)}
  end

  @doc """
  Get the count of messages filtered by args
  """
  @spec count_messages(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_messages(_, args, _) do
    {:ok, Messages.count_messages(args)}
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
  def update_message(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, message} <-
           Repo.fetch_by(Message, %{id: id, organization_id: user.organization_id}),
         {:ok, message} <- Messages.update_message(message, params) do
      {:ok, %{message: message}}
    end
  end

  @doc false
  @spec delete_message(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_message(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, message} <-
           Repo.fetch_by(Message, %{id: id, organization_id: user.organization_id}) do
      Messages.delete_message(message)
    end
  end

  @doc """
  Delete all messages of a contact
  """
  @spec clear_messages(Absinthe.Resolution.t(), %{contact_id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def clear_messages(_, %{contact_id: contact_id}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         :ok <- Messages.clear_messages(contact) do
      {:ok, %{success: true}}
    end
  end

  @doc false
  @spec create_and_send_message(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, %{message: Message.t()}}
  def create_and_send_message(_, %{input: params}, %{context: %{current_user: current_user}}) do
    with {:ok, message} <-
           params
           |> Map.merge(%{user_id: current_user.id})
           |> Messages.create_and_send_message(),
         do: {:ok, %{message: message}}
  end

  @spec send_message_to_group(map(), non_neg_integer, User.t(), atom()) ::
          {:ok | :error, map()}
  defp send_message_to_group(attrs, group_id, user, type) do
    with {:ok, group} <-
           Repo.fetch_by(Group, %{id: group_id, organization_id: user.organization_id}),
         {:ok, contact_ids} <-
           attrs
           |> Map.put(:user_id, user.id)
           |> Messages.create_and_send_message_to_group(group, type),
         do: {:ok, %{success: true, contact_ids: contact_ids}}
  end

  @doc """
  Create and send message to contacts of a group
  """
  @spec create_and_send_message_to_group(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_and_send_message_to_group(_, %{input: message_params, group_id: group_id}, %{
        context: %{current_user: current_user}
      }) do
    send_message_to_group(message_params, group_id, current_user, :session)
  end

  @doc false
  @spec send_hsm_message_to_group(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def send_hsm_message_to_group(_, %{group_id: group_id} = attrs, %{
        context: %{current_user: user}
      }) do
    send_message_to_group(
      Map.put(attrs, :user_id, user.id),
      group_id,
      user,
      :hsm
    )
  end

  @doc false
  @spec send_hsm_message(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def send_hsm_message(_, attrs, %{
        context: %{current_user: user}
      }) do
    with {:ok, message} <-
           Messages.create_and_send_hsm_message(Map.put(attrs, :user_id, user.id)),
         do: {:ok, %{message: message}}
  end

  @doc false
  @spec send_session_message(Absinthe.Resolution.t(), %{id: integer, receiver_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def send_session_message(_, %{id: id, receiver_id: receiver_id}, _) do
    with {:ok, message} <- Messages.create_and_send_session_template(id, receiver_id),
         do: {:ok, %{message: message}}
  end

  # Message Media Resolver which sits between the GraphQL schema and Glific
  # Message Context API.
  # This layer basically stitches together
  # one or more calls to resolve the incoming queries.

  @doc """
  Get a specific message media by id
  """
  @spec message_media(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def message_media(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, message_media} <-
           Repo.fetch_by(MessageMedia, %{id: id, organization_id: user.organization_id}),
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

  @doc """
  Validate a media url and type
  """
  @spec validate_media(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, map()}
  def validate_media(_, args, _) do
    {:ok, Messages.validate_media(args.url, args.type)}
  end

  @doc false
  @spec create_message_media(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_message_media(_, %{input: params}, _) do
    # lets add the default value of outbound to the flow params
    params = Map.put_new(params, :flow, :outbound)

    with {:ok, message_media} <- Messages.create_message_media(params) do
      {:ok, %{message_media: message_media}}
    end
  end

  @doc false
  @spec update_message_media(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_message_media(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, message_media} <-
           Repo.fetch_by(MessageMedia, %{id: id, organization_id: user.organization_id}),
         {:ok, message_media} <- Messages.update_message_media(message_media, params) do
      {:ok, %{message_media: message_media}}
    end
  end

  @doc false
  @spec delete_message_media(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_message_media(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, message_media} <-
           Repo.fetch_by(MessageMedia, %{id: id, organization_id: user.organization_id}) do
      Messages.delete_message_media(message_media)
    end
  end

  ## Subscriptions

  @doc false
  @spec publish_message(map(), any(), any()) ::
          {:ok, Message.t()} | {:error, any}
  def publish_message(args, _, _) do
    case args do
      %{message: message} -> {:ok, message}
      message -> {:ok, message}
    end
  end
end
