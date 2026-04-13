defmodule GlificWeb.ChatbotController do
  @moduledoc """
  Controller for the chatbot diagnostic endpoint.
  Accepts queries from a Dify chatbot, validates the API key,
  resolves the organization from the page URL, and returns query results.
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{
    ChatbotDiagnose,
    Partners.Organization,
    Repo
  }

  @doc """
  POST /dify/chatbot-diagnose

  Expects JSON body with:
    - page_url: URL containing the org shortcode as subdomain
    - tables: map of table_name => query options
    - time_range: optional time range string (e.g. "24h", "7d")

  Requires x-dify-api-key header matching the configured secret.
  """
  @spec diagnose(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def diagnose(conn, params) do
    with :ok <- verify_api_key(conn),
         {:ok, page_url} <- get_page_url(params),
         {:ok, org_id} <- resolve_organization(page_url),
         {:ok, tables} <- get_tables(params) do
      time_range = Map.get(params, "time_range")
      results = ChatbotDiagnose.run(tables, time_range, org_id)
      json(conn, %{data: results})
    else
      {:error, :unauthorized} ->
        conn |> put_status(401) |> json(%{error: "Invalid or missing API key"})

      {:error, :missing_page_url} ->
        conn |> put_status(400) |> json(%{error: "page_url is required"})

      {:error, :invalid_page_url} ->
        conn |> put_status(400) |> json(%{error: "Could not parse shortcode from page_url"})

      {:error, :org_not_found} ->
        conn |> put_status(404) |> json(%{error: "Organization not found"})

      {:error, :missing_tables} ->
        conn |> put_status(400) |> json(%{error: "tables parameter is required"})

      {:error, reason} ->
        Logger.error("ChatbotController: unexpected error: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "Internal server error"})
    end
  rescue
    e ->
      Logger.error("ChatbotController: unhandled exception: #{Exception.message(e)}")
      conn |> put_status(500) |> json(%{error: "Internal server error"})
  end

  defp verify_api_key(conn) do
    configured_key = Application.get_env(:glific, :dify_callback_api_key, "")
    request_key = get_req_header(conn, "x-dify-api-key") |> List.first()

    if configured_key != "" and request_key == configured_key do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp get_page_url(%{"page_url" => url}) when is_binary(url) and url != "", do: {:ok, url}
  defp get_page_url(_), do: {:error, :missing_page_url}

  defp get_tables(%{"tables" => tables}) when is_map(tables) and map_size(tables) > 0,
    do: {:ok, tables}

  defp get_tables(_), do: {:error, :missing_tables}

  defp resolve_organization(page_url) do
    with {:ok, shortcode} <- extract_shortcode(page_url),
         {:ok, org} <- lookup_org_by_shortcode(shortcode) do
      {:ok, org.id}
    end
  end

  @doc false
  @spec extract_shortcode(String.t()) :: {:ok, String.t()} | {:error, :invalid_page_url}
  def extract_shortcode(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        # Extract the first subdomain segment
        # e.g. "ilp.tides.coloredcow.com" → "ilp"
        case String.split(host, ".") do
          [shortcode | _rest] when shortcode != "" -> {:ok, shortcode}
          _ -> {:error, :invalid_page_url}
        end

      _ ->
        {:error, :invalid_page_url}
    end
  end

  defp lookup_org_by_shortcode(shortcode) do
    case Repo.fetch_by(Organization, %{shortcode: shortcode}, skip_organization_id: true) do
      {:ok, org} -> {:ok, org}
      _ -> {:error, :org_not_found}
    end
  end
end
