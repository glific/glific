defmodule Glific.ThirdParty.GoogleSlide.Slide do
  @moduledoc """
  Glific Google slide API layer
  """

  alias Glific.Partners

  alias Tesla

  @drive_scopes [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly",
    "https://www.googleapis.com/auth/devstorage.full_control"
  ]

  @drive_url "https://www.googleapis.com/drive/v3/files"
  @slide_url "https://slides.googleapis.com/v1/presentations"

  defp auth_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  @doc """
  Copy a Google Slides presentation and make it public.
  """
  @spec create_certificate(non_neg_integer(), String.t(), map()) ::
          {:ok, any()} | {:error, any()}
  def create_certificate(org_id, presentation_id, fields) do
    with token <-
           Partners.get_goth_token(org_id, "google_cloud_storage", scopes: @drive_scopes).token,
         {:ok, copied_slide} <- copy_slide(token, presentation_id),
         {:ok, _} <- make_public(token, copied_slide["id"]),
         {:ok, _} <- replace_text(token, copied_slide["id"], fields),
         {:ok, data} <- thumbnail(token, copied_slide["id"]) do
      {:ok, data["contentUrl"]}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_slide(token, presentation_id) do
    url = "#{@drive_url}/#{presentation_id}/copy"

    headers = auth_headers(token)

    case Tesla.post(url, "{}", headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded_body} -> {:ok, decoded_body}
          {:error, decode_error} -> {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %Tesla.Env{status: status_code, body: response_body}} ->
        {:error,
         "Failed to copy slide. Status: #{status_code}, Response: #{inspect(response_body)}"}

      {:error, error} ->
        {:error, "HTTP request failed: #{inspect(error)}"}
    end
  end

  @spec make_public(binary(), String.t()) :: {:ok, any()} | {:error, any()}
  defp make_public(token, presentation_id) do
    url = "#{@drive_url}/#{presentation_id}/permissions"

    headers = auth_headers(token)

    body =
      Jason.encode!(%{
        "role" => "writer",
        "type" => "anyone"
      })

    case Tesla.post(url, body, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status_code, body: response_body}} ->
        {:error,
         "Failed to update permissions. Status: #{status_code}, Response: #{inspect(response_body)}"}

      {:error, error} ->
        {:error, "HTTP request failed: #{inspect(error)}"}
    end
  end

  defp replace_text(token, presentation_id, fields) do
    url = "#{@slide_url}/#{presentation_id}:batchUpdate"
    headers = auth_headers(token)

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

    body = %{"requests" => requests} |> Jason.encode!()

    case Tesla.post(url, body, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status_code, body: response_body}} ->
        {:error,
         "Failed to update text. Status: #{status_code}, Response: #{inspect(response_body)}"}

      {:error, error} ->
        {:error, "HTTP request failed: #{inspect(error)}"}
    end
  end

  defp thumbnail(token, presentation_id) do
    url = "#{@slide_url}/#{presentation_id}/pages/p2/thumbnail"
    headers = auth_headers(token)

    case Tesla.get(url, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to fetch thumbnail. Status: #{status_code}, Response: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Failed to fetch thumbnail"}
    end
  end
end
