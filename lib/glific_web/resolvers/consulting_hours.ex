defmodule GlificWeb.Resolvers.ConsultingHours do
  @moduledoc """
  Consulting Hours Resolver which sits between the GraphQL schema and Glific Consulting Hour Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  import GlificWeb.Gettext
  alias Glific.{Repo, Saas.ConsultingHour}

  @doc """
  Fetch consulting hour based id
  """
  @spec get_consulting_hours(Absinthe.Resolution.t(), %{id: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_consulting_hours(_, %{id: id}, _) do
    with consulting_hour <-
           ConsultingHour.get_consulting_hour(%{id: id}),
         false <- is_nil(consulting_hour) do
      {:ok, %{consulting_hour: consulting_hour}}
    else
      _ ->
        {:error, dgettext("errors", "No consulting hour found with inputted params")}
    end
  end

  @doc """
  Get the list of consulting hour filtered by args
  """
  @spec consulting_hours(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [ConsultingHour]}
  def consulting_hours(_, args, _) do
    {:ok, ConsultingHour.list_consulting_hours(args)}
  end

  @doc """
  Get the count of consulting hours filtered by args
  """
  @spec count_consulting_hours(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_consulting_hours(_, args, _) do
    {:ok, ConsultingHour.count_consulting_hours(args)}
  end

  @doc """
  Create consulting hour
  """
  @spec create_consulting_hour(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_consulting_hour(_, %{input: params}, _) do
    with {:ok, consulting_hour} <- ConsultingHour.create_consulting_hour(params) do
      {:ok, %{consulting_hour: consulting_hour}}
    end
  end

  @doc """
  Update consulting hour
  """
  @spec update_consulting_hour(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_consulting_hour(_, %{id: id, input: params}, _) do
    with {:ok, consulting_hour} <-
           Repo.fetch_by(ConsultingHour, %{id: id}),
         {:ok, consulting_hour} <- ConsultingHour.update_consulting_hour(consulting_hour, params) do
      {:ok, %{consulting_hour: consulting_hour}}
    end
  end

  @doc """
  Delete consulting hour
  """
  @spec delete_consulting_hour(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_consulting_hour(_, %{id: id}, _) do
    with {:ok, consulting_hour} <- Repo.fetch_by(ConsultingHour, %{id: id}),
         {:ok, consulting_hour} <- ConsultingHour.delete_consulting_hour(consulting_hour) do
      {:ok, %{consulting_hour: consulting_hour}}
    end
  end
end
