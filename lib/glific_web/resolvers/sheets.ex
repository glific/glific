defmodule GlificWeb.Resolvers.Sheets do
  @moduledoc """
  Trigger Resolver which sits between the GraphQL schema and Glific Sheets Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Repo,
    Sheets,
    Sheets.Sheet
  }

  @doc false
  @spec sheet(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def sheet(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, sheet} <-
           Repo.fetch_by(Sheet, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{sheet: sheet}}
  end

  @doc """
  Get the list of sheets filtered by args
  """
  @spec sheets(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def sheets(_, args, _) do
    {:ok, Sheets.list_sheets(args)}
  end

  @doc """
  Get the count of sheets filtered by args
  """
  @spec count_sheets(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_sheets(_, args, _) do
    {:ok, Sheets.count_sheets(args)}
  end

  @doc false
  @spec create_sheet(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_sheet(_, %{input: params}, _) do
    with {:ok, sheet} <- Sheets.create_sheet(params) do
      {:ok, %{sheet: sheet}}
    end
  end

  @doc false
  @spec update_sheet(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_sheet(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, sheet} <-
           Repo.fetch_by(Sheet, %{id: id, organization_id: user.organization_id}),
         {:ok, sheet} <- Sheets.update_sheet(sheet, params) do
      {:ok, %{sheet: sheet}}
    end
  end

  @doc false
  @spec sync_sheet(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def sync_sheet(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, sheet} <-
           Repo.fetch_by(Sheet, %{id: id, organization_id: user.organization_id}) do
      Sheets.sync_sheet_data(sheet)

      {:ok, %{sheet: sheet}}
    end
  end

  @doc false
  @spec delete_sheet(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_sheet(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, sheet} <- Repo.fetch_by(Sheet, %{id: id, organization_id: user.organization_id}) do
      Sheets.delete_sheet(sheet)
    end
  end
end
