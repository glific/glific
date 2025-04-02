defmodule Glific.ThirdParty.GoogleSlide.Slide do
  @moduledoc """
  Glific Google slide API layer
  """
  require Logger

  alias Glific.{
    Partners,
    Repo
  }

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
      delete_template_copy(token, copied_slide["id"], org_id)
      {:ok, data["contentUrl"]}
    else
      {:error, reason} ->
        Logger.error(
          "Certificate creation failed for org_id: #{org_id}, Error: #{inspect(reason)}"
        )

        {:error, reason}

      _ ->
        Logger.error(
          "Certificate creation failed for org_id: #{org_id}, Error: Failed to get Google Slides goth token"
        )

        {:error, "Failed to get Google Slides goth token"}
    end
  end

  @doc """
  Parses the slides url

  ## Examples
      iex> Glific.ThirdParty.GoogleSlide.Slide.parse_slides_url("https://docs.google.com/presentation/d/1aF1ldS4zjEHmM4LqHfGEW7TfGacBL4dyBfgIadp4/edit#slide=id.p")
      {:error, "Template url not a valid Google Slides url"}
      iex> Glific.ThirdParty.GoogleSlide.Slide.parse_slides_url("https://docs.google.com/presentation/d/1UllxeYCFhetMS6_WwkmuKeWRiwbttXfJU1bp22aiaOk/edit#slide=id.g33e095ed7be_2_75")
      {:ok, %{presentation_id: "1UllxeYCFhetMS6_WwkmuKeWRiwbttXfJU1bp22aiaOk", page_id: "g33e095ed7be_2_75"}}
      iex> Glific.ThirdParty.GoogleSlide.Slide.parse_slides_url("https://docs.google.com/presentation/d/1UllxeYCFhetMS6_WwkmuKeWRiwbttXfJU1bp22aiaOk/edit#slide=id.g33e095ed7be_2_75")
      {:ok, %{presentation_id: "1UllxeYCFhetMS6_WwkmuKeWRiwbttXfJU1bp22aiaOk", page_id: "g33e095ed7be_2_75"}}
      iex> Glific.ThirdParty.GoogleSlide.Slide.parse_slides_url("https://docs.google.com/presentation/d/1qHobEu0HbRHpiHJbqAEvu_M13YvJ1qWIWiAcWXXXBFk/edit?slide=id.g33e0d0c1143_0_0#slide=id.g33e0d0c1143_0_0")
      {:ok, %{presentation_id: "1qHobEu0HbRHpiHJbqAEvu_M13YvJ1qWIWiAcWXXXBFk", page_id: "g33e0d0c1143_0_0"}}
      iex> Glific.ThirdParty.GoogleSlide.Slide.parse_slides_url("https://docs.google.com/presentation/d/1qHobEu0HbRHpiHJbqAEvu_M13YvJ1qWIWiAcWXXXBFk/edit?slide=id.g33e0d0c1143_0_0")
      {:ok, %{presentation_id: "1qHobEu0HbRHpiHJbqAEvu_M13YvJ1qWIWiAcWXXXBFk", page_id: "g33e0d0c1143_0_0"}}
  """
  @spec parse_slides_url(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_slides_url(url) do
    with [_, presentation_id] <-
           Regex.run(~r{https://docs.google.com/presentation/d/([a-zA-Z0-9_-]+)/}, url),
         [_, page_id] <- Regex.run(~r/slide=id\.(g[a-zA-Z0-9_-]+)/, url) do
      {:ok,
       %{
         presentation_id: presentation_id,
         page_id: page_id
       }}
    else
      _ -> {:error, "Template url not a valid Google Slides url"}
    end
  end

  @doc """
  Get the details of the slide, given presentation_id

  The details are fetched from google drive using drives api.
  """
  @spec get_file(non_neg_integer(), String.t()) :: {:ok, any()} | {:error, String.t()}
  def get_file(org_id, presentation_id) do
    url = "#{@drive_url}/#{presentation_id}"

    with %{token: token} <-
           Partners.get_goth_token(org_id, "google_slides", scopes: @drive_scopes),
         {:ok, %Tesla.Env{status: 200, body: body}} <-
           Tesla.get(client(), url, headers: auth_headers(token)) do
      {:ok, body}
    else
      err when is_tuple(err) ->
        {:error, "Unable to fetch the slide"}

      _ ->
        {:error, "Failed to get Google Slides goth token"}
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
  @spec client :: Tesla.Client.t()
  defp client do
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

  @spec delete_template_copy(String.t(), String.t(), integer()) :: any()
  defp delete_template_copy(token, presentation_id, org_id) do
    Task.Supervisor.start_child(Glific.TaskSupervisor, fn ->
      Repo.put_process_state(org_id)
      delete_url = "#{@drive_url}/#{presentation_id}"

      case Tesla.delete(client(), delete_url, headers: auth_headers(token)) do
        {:ok, %Tesla.Env{status: status, body: _body}} when status >= 200 and status < 400 ->
          :ok

        {:ok, %Tesla.Env{status: status, body: body}} ->
          Logger.error(
            "Failed to delete the template copy. Status: #{status}, Response: #{inspect(body)} "
          )

        {:error, error} ->
          Logger.error("Failed to delete the template copy: #{inspect(error)}")
      end
    end)
  end
end
