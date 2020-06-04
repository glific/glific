defmodule GlificWeb.Resolvers.Settings do
  @moduledoc """
  Settings Resolver which sits between the GraphQL schema and Glific Settings Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Settings, Settings.Language}

  @spec languages(Absinthe.Resolution.t(), %{atom => any}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def languages(_, args, _) do
    {:ok, Settings.list_languages(args)}
  end

  @spec search(Absinthe.Resolution.t(), %{matching: String.t()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def search(_, %{matching: _term}, _) do
    # {:ok, Tags.search(term)}
    {:ok, %{}}
  end

  @spec create_language(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_language(_, %{input: params}, _) do
    with {:ok, language} <- Settings.create_language(params) do
      {:ok, %{language: language}}
    end
  end

  @spec update_language(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_language(_, %{id: id, input: params}, _) do
    with {:ok, language} <- Repo.fetch(Language, id),
         {:ok, language} <- Settings.update_language(language, params) do
      {:ok, %{language: language}}
    end
  end
end
