defmodule Glific.ThirdParty.GoogleSlide.Slide do
  @moduledoc """
  Glific Google slide API layer
  """
  require Logger

  alias Glific.Partners
  alias Tesla

  @drive_scopes [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly"
  ]

  @drive_url "https://www.googleapis.com/drive/v3/files"
  @slide_url "https://slides.googleapis.com/v1/presentations"

  @spec auth_headers(String.t()) :: list()
  defp auth_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  @doc """
  create custom certificate
  """
  @spec create_certificate(non_neg_integer(), String.t(), map(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def create_certificate(org_id, presentation_id, fields, slide_id) do
    with %{token: token} <-
           Partners.get_goth_token(org_id, "google_slides", scopes: @drive_scopes),
         {:ok, copied_slide} <- copy_slide(token, presentation_id),
         {:ok, _} <- replace_text(token, copied_slide["id"], fields),
         {:ok, data} <- fetch_thumbnail(token, copied_slide["id"], slide_id) do
      {:ok, data["contentUrl"]}
    else
      {:error, reason} ->
        Logger.error(
          "Certificate creation failed for org_id: #{org_id}, Error: #{inspect(reason)}"
        )

        {:error, reason}

      _ ->
        Logger.error(
          "Certificate creation failed for org_id: #{org_id}, Error: Failed to get goth token"
        )

        {:error, "Failed to get goth token"}
    end
  end

  @spec copy_slide(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp copy_slide(token, presentation_id) do
    url = "#{@drive_url}/#{presentation_id}/copy"
    headers = auth_headers(token)

    case Tesla.post(client(), url, "{}", headers: headers) do

      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded_body} -> {:ok, decoded_body}
          {:error, decode_error} -> {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %Tesla.Env{status: status_code, body: response_body}} ->
        {:error,
         "Failed to copy slide. Status: #{status_code}, Response: #{inspect(response_body)}"}

      {:error, error} ->
        {:error, "HTTP request failed while copying slide: #{inspect(error)}"}
    end
  end

  @spec replace_text(String.t(), String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp replace_text(token, presentation_id, fields) do
    url = "#{@slide_url}/#{presentation_id}:batchUpdate"

    requests =
      fields
      |> Enum.map(fn {placeholder, replace_text} ->
        %{
          "replaceAllText" => %{
            "replaceText" => replace_text,
            "containsText" => %{
              "text" => placeholder,
              "matchCase" => true
            }
          }
        }
      end)

    body = Jason.encode!(%{"requests" => requests})

    case Tesla.post(client(), url, body, headers: auth_headers(token)) do

      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status_code, body: response_body}} ->
        {:error,
         "Failed to update text. Status: #{status_code}, Response: #{inspect(response_body)}"}

      {:error, error} ->
        {:error, "HTTP request failed while replacing text: #{inspect(error)}"}
    end
  end

  @spec fetch_thumbnail(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp fetch_thumbnail(token, presentation_id, slide_id) do
    url = "#{@slide_url}/#{presentation_id}/pages/#{slide_id}/thumbnail"

    case Tesla.get(client(), url, headers: auth_headers(token)) do

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to fetch thumbnail. Status: #{status}, Response: #{inspect(body)}"}

      {:error, error} ->
        {:error, "HTTP request failed while fetching thumbnail: #{inspect(error)}"}
    end
  end

  # https://hexdocs.pm/tesla/Tesla.Middleware.Retry.html
  @spec client() :: Tesla.Client.t()
  defp client() do
    Tesla.client([
      {
        Tesla.Middleware.Retry,
        delay: 500,
        max_retries: 3,
        should_retry: fn
          {:ok, %{status: status}}, _, _ when status in 501..504 ->
            true

          {:error, reason}, _, _ when reason in [:timeout, :connrefused, :nxdomain] ->
            true

          _, _, _ ->
            false
        end
      }
    ])
  end

end
