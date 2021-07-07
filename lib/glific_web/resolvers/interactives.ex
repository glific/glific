defmodule GlificWeb.Resolvers.Interactives do
  @moduledoc """
  Templates Resolver which sits between the GraphQL schema and Glific Interactives Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """
  alias Glific.{Repo, Interactives, Messages.Interactive}

  @doc """
  Get the list of session templates filtered by args
  """
  @spec interactives(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def interactives(_, args, _) do
    {:ok, Interactives.list_interactives(args)}
  end

  @doc """
  Get the count of session templates filtered by args
  """
  @spec count_interactives(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_interactives(_, args, _) do
    {:ok, Interactives.count_interactives(args)}
  end
end
