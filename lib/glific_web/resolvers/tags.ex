defmodule GlificWeb.Resolvers.Tags do
  @moduledoc """
  Tag Resolver which sits between the GraphQL schema and Glific Tag Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Tags, Tags.Tag}

  @spec tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tag(_, %{id: id}, _) do
    with {:ok, tag} <- Repo.fetch(Tag, id),
         do: {:ok, %{tag: tag}}
  end

  @spec tags(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tags(_, args, _) do
    {:ok, Tags.list_tags(args)}
  end

  @spec search(Absinthe.Resolution.t(), %{matching: String.t()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def search(_, %{matching: _term}, _) do
    # {:ok, Tags.search(term)}
    {:ok, %{}}
  end

  @spec tags_for_language(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def tags_for_language(language, _, _) do
    query = Ecto.assoc(language, :tags)
    {:ok, Repo.all(query)}
  end

  @spec create_tag(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_tag(_, %{input: params}, _) do
    with {:ok, tag} <- Tags.create_tag(params) do
      {:ok, %{tag: tag}}
    end
  end

  @spec update_tag(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_tag(_, %{id: id, input: params}, _) do
    with {:ok, tag} <- Repo.fetch(Tag, id),
         {:ok, tag} <- Tags.update_tag(tag, params) do
      {:ok, %{tag: tag}}
    end
  end

  @spec delete_tag(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_tag(_, %{id: id}, _) do
    with {:ok, tag} <- Repo.fetch(Tag, id),
         {:ok, tag} <- Tags.delete_tag(tag) do
      {:ok, tag}
    end
  end
end
