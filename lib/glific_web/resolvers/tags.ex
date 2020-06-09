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
  @spec tags(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tags(_, args, _) do
    {:ok, Tags.list_tags(args)}
  end

  @doc """
  Get the list of objects in the database that match the term
  """
  @spec search(Absinthe.Resolution.t(), %{matching: String.t()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def search(_, %{matching: _term}, _) do
    # {:ok, Tags.search(term)}
    {:ok, %{}}
  end

  @doc """
  Get all the tags associated with a specific language
  """
  @spec tags_for_language(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tags_for_language(language, _, _) do
    query = Ecto.assoc(language, :tags)
    {:ok, Repo.all(query)}
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
end
