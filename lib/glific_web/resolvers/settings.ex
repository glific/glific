defmodule GlificWeb.Resolvers.Settings do
  @moduledoc """
  Settings Resolver which sits between the GraphQL schema and Glific Settings Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Settings, Settings.Language}

  @doc """
  Get a specific language by id
  """
  @spec language(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def language(_, %{id: id}, _) do
    with {:ok, language} <- Repo.fetch(Language, id, skip_organization_id: true),
         do: {:ok, %{language: language}}
  end

  @doc """
  Get the list of languages filtered by args
  """
  @spec languages(Absinthe.Resolution.t(), %{atom => any}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def languages(_, args, _) do
    {:ok, Settings.list_languages(args)}
  end

  @doc """
  Get the count of languages filtered by args
  """
  @spec count_languages(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_languages(_, args, _) do
    {:ok, Settings.count_languages(args)}
  end

  @doc """
  Create a new language. Since language is a basic system data type, this operation is an upsert
  """
  @spec create_language(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_language(_, %{input: params}, _) do
    with {:ok, language} <- Settings.create_language(params) do
      {:ok, %{language: language}}
    end
  end

  @doc """
  Update language data fields
  """
  @spec update_language(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_language(_, %{id: id, input: params}, _) do
    with {:ok, language} <- Repo.fetch(Language, id, skip_organization_id: true),
         {:ok, language} <- Settings.update_language(language, params) do
      {:ok, %{language: language}}
    end
  end

  @doc false
  @spec delete_language(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_language(_, %{id: id}, _) do
    with {:ok, language} <- Repo.fetch(Language, id, skip_organization_id: true),
         {:ok, language} <- Settings.delete_language(language) do
      {:ok, language}
    end
  end
end
