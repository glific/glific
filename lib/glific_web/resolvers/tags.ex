defmodule GlificWeb.Resolvers.Tags do
  @moduledoc """
  Tag Resolver which sits between the GraphQL schema and Glific Tag Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Tags, Tags.Tag}
  alias Glific.{Tags.ContactTag, Tags.MessageTag}

  @doc """
  Get a specific tag by id
  """
  @spec tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tag(_, %{id: id}, _) do
    with {:ok, tag} <- Repo.fetch(Tag, id),
         do: {:ok, %{tag: tag}}
  end

  @doc """
  Get the list of tags filtered by args
  """
  @spec tags(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Tag]}
  def tags(_, args, _) do
    {:ok, Tags.list_tags(args)}
  end

  @doc """
  Get the count of tags filtered by args
  """
  @spec count_tags(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_tags(_, args, _) do
    {:ok, Tags.count_tags(args)}
  end

  @doc false
  @spec create_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_tag(_, %{input: params}, _) do
    with {:ok, tag} <- Tags.create_tag(params) do
      {:ok, %{tag: tag}}
    end
  end

  @doc false
  @spec update_tag(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_tag(_, %{id: id, input: params}, _) do
    with {:ok, tag} <- Repo.fetch(Tag, id),
         {:ok, tag} <- Tags.update_tag(tag, params) do
      {:ok, %{tag: tag}}
    end
  end

  @doc false
  @spec delete_tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_tag(_, %{id: id}, _) do
    with {:ok, tag} <- Repo.fetch(Tag, id),
         {:ok, tag} <- Tags.delete_tag(tag) do
      {:ok, tag}
    end
  end

  @doc false
  @spec create_message_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_message_tag(_, %{input: params}, _) do
    with {:ok, message_tag} <- Tags.create_message_tag(params) do
      {:ok, %{message_tag: message_tag}}
    end
  end

  @doc false
  @spec update_message_tags(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_message_tags(_, %{input: params}, _) do
    message_tags = Tags.MessageTags.update_message_tags(params)
    {:ok, message_tags}
  end

  @doc false
  @spec delete_message_tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_message_tag(_, %{id: id}, _) do
    with {:ok, message_tag} <- Repo.fetch(MessageTag, id),
         {:ok, message_tag} <- Tags.delete_message_tag(message_tag) do
      {:ok, message_tag}
    end
  end

  @doc false
  @spec create_contact_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_tag(_, %{input: params}, _) do
    with {:ok, contact_tag} <- Tags.create_contact_tag(params) do
      {:ok, %{contact_tag: contact_tag}}
    end
  end

  @doc false
  @spec delete_contact_tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_contact_tag(_, %{id: id}, _) do
    with {:ok, contact_tag} <- Repo.fetch(ContactTag, id),
         {:ok, contact_tag} <- Tags.delete_contact_tag(contact_tag) do
      {:ok, contact_tag}
    end
  end

  @doc false
  @spec mark_all_message_as_read(Absinthe.Resolution.t(), %{contact_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def mark_all_message_as_read(_, %{contact_id: contact_id}, _) do
    with untag_message_ids <- Tags.remove_tag_from_all_message(contact_id, "Unread"),
         do: {:ok, untag_message_ids}
  end
end
