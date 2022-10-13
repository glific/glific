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
  def update_sheet(_, %{id: id, label: label}, %{context: %{current_user: user}}) do
    with {:ok, sheet} <-
           Repo.fetch_by(Sheet, %{id: id, organization_id: user.organization_id}),
         {:ok, sheet} <- Sheets.update_sheet(sheet, %{label: label}) do
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
