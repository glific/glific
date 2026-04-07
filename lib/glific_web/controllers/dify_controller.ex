defmodule GlificWeb.DifyController do
  @moduledoc """
  Controller for Dify callback endpoints.
  Authenticated via `x-dify-api-key` header (not user session tokens).
  """

  use GlificWeb, :controller

  require Logger

  alias Glific.{DifyTableQuery, Partners, Repo}

  @doc """
  Handles chatbot diagnose requests from Dify.
  Accepts a dynamic table query spec and returns matching rows.

  Expects JSON body:
    - page_url (required): used to extract org shortcode from subdomain
    - tables (required): map of table_name => %{filters, fields, limit, order}
    - time_range (optional): "1h", "24h", "3d", "7d", "30d"
  """
  @spec chatbot_diagnose(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def chatbot_diagnose(conn, params) do
    with {:ok, page_url} <- require_param(params, "page_url"),
         {:ok, tables} <- require_param(params, "tables"),
         {:ok, shortcode} <- extract_shortcode(page_url),
         {:ok, organization} <- fetch_organization("glific") do
      Repo.put_organization_id(organization.id)

      time_range = Map.get(params, "time_range", "24h")

      {:ok, result} = DifyTableQuery.query_tables(organization.id, tables, time_range)
      json(conn, %{data: result})
    else
      {:error, message} ->
        conn
        |> put_status(400)
        |> json(%{error: message})
    end
  rescue
    e ->
      Logger.error("DifyController chatbot_diagnose error: #{Exception.message(e)}")

      conn
      |> put_status(500)
      |> json(%{error: "An unexpected error occurred"})
  end

  defp require_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "Missing required parameter: #{key}"}
      "" -> {:error, "Missing required parameter: #{key}"}
      value -> {:ok, value}
    end
  end

  @spec extract_shortcode(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp extract_shortcode(page_url) do
    case URI.parse(page_url) do
      %URI{host: host} when is_binary(host) ->
        shortcode = host |> String.split(".") |> List.first()

        if shortcode && shortcode != "" do
          {:ok, shortcode}
        else
          {:error, "Could not extract shortcode from page_url"}
        end

      _ ->
        {:error, "Invalid page_url"}
    end
  end

  @spec fetch_organization(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp fetch_organization(shortcode) do
    case Partners.organization(shortcode) do
      {:error, _} -> {:error, "Organization not found for shortcode: #{shortcode}"}
      nil -> {:error, "Organization not found for shortcode: #{shortcode}"}
      organization -> {:ok, organization}
    end
  end
end
