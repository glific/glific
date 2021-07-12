defmodule GlificWeb.Resolvers.InterativeTemplates do
  @moduledoc """
  Interactives Resolver which sits between the GraphQL schema and Glific Interactives Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """
  alias Glific.{
  Repo,
  Templates.InteractiveTemplates,
  Templates.InterativeTemplate
}

  @doc """
  Get a specific session template by id
  """
  @spec interactive(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def interactive(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, interactive} <-
           Repo.fetch_by(InterativeTemplate, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{interactive: interactive}}
  end

  @doc """
  Get the list of session Interactives filtered by args
  """
  @spec interactives(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def interactives(_, args, _) do
    {:ok, InteractiveTemplates.list_interactives(args)}
  end

  @doc """
  Get the count of session Interactives filtered by args
  """
  @spec count_interactives(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_interactives(_, args, _) do
    {:ok, InteractiveTemplates.count_interactives(args)}
  end

  @doc false
  @spec create_interactive(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_interactive(_, %{input: params}, _) do
    with {:ok, interactive} <- InteractiveTemplates.create_interactive(params) do
      {:ok, %{interactive: interactive}}
    end
  end

  @doc false
  @spec update_interactive(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_interactive(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, interactive} <-
           Repo.fetch_by(InterativeTemplate, %{id: id, organization_id: user.organization_id}),
         {:ok, interactive} <- InteractiveTemplates.update_interactive(interactive, params) do
      {:ok, %{interactive: interactive}}
    end
  end

  @doc false
  @spec delete_interactive(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_interactive(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, interactive} <-
           Repo.fetch_by(InterativeTemplate, %{id: id, organization_id: user.organization_id}),
         {:ok, interactive} <- InteractiveTemplates.delete_interactive(interactive) do
      {:ok, interactive}
    end
  end
end
