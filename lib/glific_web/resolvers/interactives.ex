defmodule GlificWeb.Resolvers.InteractiveTemplates do
  @moduledoc """
  Interactives Resolver which sits between the GraphQL schema and Glific Interactives Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """
  alias Glific.{
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates
  }

  @doc """
  Get a specific session template by id
  """
  @spec interactive_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def interactive_template(_, %{id: id}, _) do
    with {:ok, interactive_template} <-
           InteractiveTemplates.fetch_interactive_template(id),
         do: {:ok, %{interactive_template: interactive_template}}
  end

  @doc """
  Get the list of session Interactives filtered by args
  """
  @spec interactive_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def interactive_templates(_, args, _) do
    {:ok, InteractiveTemplates.list_interactives(args)}
  end

  @doc """
  Get the count of session Interactives filtered by args
  """
  @spec count_interactive_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_interactive_templates(_, args, _) do
    {:ok, InteractiveTemplates.count_interactive_templates(args)}
  end

  @doc false
  @spec create_interactive_template(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_interactive_template(_, %{input: params}, _) do
    with {:ok, interactive_template} <- InteractiveTemplates.create_interactive_template(params) do
      {:ok, %{interactive_template: interactive_template}}
    end
  end

  @doc false
  @spec update_interactive_template(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_interactive_template(_, %{id: id, input: params}, _) do
    with {:ok, interactive_template} <-
           InteractiveTemplates.fetch_interactive_template(id),
         {:ok, interactive_template} <-
           InteractiveTemplates.update_interactive_template(interactive_template, params) do
      {:ok, %{interactive_template: interactive_template}}
    end
  end

  @doc false
  @spec delete_interactive_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_interactive_template(_, %{id: id}, _) do
    with {:ok, interactive_template} <-
           InteractiveTemplates.fetch_interactive_template(id) do
      InteractiveTemplates.delete_interactive_template(interactive_template)
    end
  end

  @doc """
  Make a copy of interactive template
  """
  @spec copy_interactive_template(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def copy_interactive_template(_, %{id: id, input: params}, _) do
    do_copy_interactive_template(
      id,
      params,
      &InteractiveTemplates.copy_interactive_template/2
    )
  end

  @spec do_copy_interactive_template(
          non_neg_integer,
          map(),
          (InteractiveTemplate.t(), map() ->
             {:ok, InteractiveTemplate.t()} | {:error, String.t()})
        ) :: {:ok, any} | {:error, any}
  defp do_copy_interactive_template(id, params, fun) do
    with {:ok, interactive_template} <-
           InteractiveTemplates.fetch_interactive_template(id),
         {:ok, interactive_template} <- fun.(interactive_template, params) do
      {:ok, %{interactive_template: interactive_template}}
    end
  end
end
