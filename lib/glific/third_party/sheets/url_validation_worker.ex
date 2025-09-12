defmodule Glific.Sheets.UrlValidationWorker do
  @moduledoc """
  Async worker to validate media URLs from Google Sheets.
  This prevents API timeouts during sheet sync operations.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 3

  require Logger

  alias Glific.{
    Messages,
    Notifications,
    Sheets.Sheet,
    Repo
  }

  @doc """
  Perform async URL validation for a sheet's media URLs
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "sheet_id" => sheet_id,
          "organization_id" => organization_id,
          "media_urls" => media_urls
        }
      }) do
    sheet = Repo.get!(Sheet, sheet_id)
    
    invalid_urls = validate_media_urls(media_urls, organization_id)
    
    if map_size(invalid_urls) > 0 do
      create_validation_notification(sheet, invalid_urls)
    end
    
    :ok
  end

  @spec validate_media_urls(map(), non_neg_integer()) :: map()
  defp validate_media_urls(media_urls, organization_id) do
    media_urls
    |> Enum.reduce(%{}, fn {url, _row_info}, acc ->
      case validate_single_url(url, organization_id) do
        {:error, message} -> Map.put(acc, url, message)
        :ok -> acc
      end
    end)
  end

  @spec validate_single_url(String.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  defp validate_single_url(url, _organization_id) do
    {media_type, _media} = Messages.get_media_type_from_url(url, log_error: false)
    
    if media_type != :text do
      case Messages.validate_media(url, Atom.to_string(media_type)) do
        %{is_valid: false, message: message} ->
          {:error, message}
        _ ->
          :ok
      end
    else
      :ok
    end
  end

  @spec create_validation_notification(Sheet.t(), map()) :: :ok
  defp create_validation_notification(sheet, invalid_urls) do
    message = format_validation_message(invalid_urls)
    
    Notifications.create_notification(%{
      category: "Google sheets",
      message: message,
      severity: Notifications.types().warning,
      organization_id: sheet.organization_id,
      entity: %{
        sheet_id: sheet.id,
        sheet_label: sheet.label,
        sheet_url: sheet.url,
        invalid_urls: invalid_urls
      }
    })
    
    :ok
  end

  @spec format_validation_message(map()) :: String.t()
  defp format_validation_message(invalid_urls) do
    count = map_size(invalid_urls)
    
    urls_summary = 
      invalid_urls
      |> Enum.take(3)
      |> Enum.map(fn {url, error} -> 
        "• #{url}: #{error}"
      end)
      |> Enum.join("\n")
    
    base_message = "Found #{count} invalid media URL(s) in the sheet:\n#{urls_summary}"
    
    if count > 3 do
      base_message <> "\n... and #{count - 3} more invalid URL(s)"
    else
      base_message
    end
  end
end