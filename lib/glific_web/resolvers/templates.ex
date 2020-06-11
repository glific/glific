defmodule GlificWeb.Resolvers.Templates do
  @moduledoc """
  Templates Resolver which sits between the GraphQL schema and Glific Templates Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Templates, Templates.SessionTemplate}

  @doc """
  Get a specific session template by id
  """
  @spec session_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def session_template(_, %{id: id}, _) do
    with {:ok, session_template} <- Repo.fetch(SessionTemplate, id),
         do: {:ok, %{session_template: session_template}}
  end

  @doc """
  Get the list of session templates filtered by args
  """
  @spec session_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def session_templates(_, args, _) do
    {:ok, Templates.list_session_templates(args)}
  end

  @doc false
  @spec create_session_template(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_session_template(_, %{input: params}, _) do
    with {:ok, session_template} <- Templates.create_session_template(params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec update_session_template(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_session_template(_, %{id: id, input: params}, _) do
    with {:ok, session_template} <- Repo.fetch(SessionTemplate, id),
         {:ok, session_template} <- Templates.update_session_template(session_template, params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec delete_session_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_session_template(_, %{id: id}, _) do
    with {:ok, session_template} <- Repo.fetch(SessionTemplate, id),
         {:ok, session_template} <- Templates.delete_session_template(session_template) do
      {:ok, session_template}
    end
  end
end
