defmodule Glific.Sheets.UrlValidationWorker do
  @moduledoc """
  Async worker to validate media URLs from Google Sheets.
  Queries URLs from database to avoid memory issues with large sheets.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 3

  require Logger
  import Ecto.Query

  alias Glific.{
    Messages,
    Notifications,
    Repo,
    Sheets.Sheet,
    Sheets.SheetData
  }

  @batch_size 100
  @concurrent_validations 10

  @doc """
  Perform async URL validation by querying sheet data from database
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "sheet_id" => sheet_id,
          "organization_id" => organization_id
        }
      }) do
    sheet = Repo.get!(Sheet, sheet_id)

    Logger.info("Starting URL validation for sheet #{sheet.label} (id: #{sheet_id})")

    # Stream sheet data and validate URLs in batches
    invalid_urls =
      SheetData
      |> where([sd], sd.sheet_id == ^sheet_id)
      |> where([sd], sd.organization_id == ^organization_id)
      |> Repo.stream(max_rows: @batch_size)
      |> Stream.flat_map(&extract_media_urls_from_row/1)
      |> Stream.chunk_every(@concurrent_validations)
      |> Stream.map(&validate_url_batch/1)
      |> Enum.reduce(%{}, fn batch_results, acc ->
        Map.merge(acc, batch_results)
      end)

    # Create notification if there are invalid URLs
    if map_size(invalid_urls) > 0 do
      create_validation_notification(sheet, invalid_urls)
    end

    Logger.info(
      "Completed URL validation for sheet #{sheet.label}. Found #{map_size(invalid_urls)} invalid URLs"
    )

    :ok
  rescue
    error ->
      Logger.error("Error validating URLs for sheet #{sheet_id}: #{inspect(error)}")
      {:error, error}
  end

  @spec extract_media_urls_from_row(SheetData.t()) :: list({String.t(), map()})
  defp extract_media_urls_from_row(sheet_data) do
    sheet_data.row_data
    |> Enum.filter(fn {_key, value} ->
      is_binary(value) && String.starts_with?(value, ["http://", "https://"])
    end)
    |> Enum.map(fn {key, url} ->
      {media_type, _} = Messages.get_media_type_from_url(url, log_error: false)

      if media_type != :text do
        {url,
         %{
           row_key: sheet_data.key,
           column: key,
           media_type: Atom.to_string(media_type)
         }}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec validate_url_batch(list({String.t(), map()})) :: map()
  defp validate_url_batch(url_batch) do
    url_batch
    |> Task.async_stream(
      fn {url, metadata} ->
        case validate_single_url(url, metadata.media_type) do
          {:error, message} ->
            {url, Map.put(metadata, :error, message)}

          :ok ->
            nil
        end
      end,
      max_concurrency: @concurrent_validations,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, nil}, acc ->
        acc

      {:ok, {url, metadata}}, acc ->
        Map.put(acc, url, metadata)

      {:exit, :timeout}, acc ->
        Logger.warning("URL validation timeout in batch")
        acc

      _, acc ->
        acc
    end)
  end

  @spec validate_single_url(String.t(), String.t()) :: :ok | {:error, String.t()}
  defp validate_single_url(url, media_type) do
    case Messages.validate_media(url, media_type) do
      %{is_valid: false, message: message} ->
        {:error, message}

      %{is_valid: true} ->
        :ok

      _ ->
        {:error, "Unknown validation error"}
    end
  end

  @spec create_validation_notification(Sheet.t(), map()) :: :ok
  defp create_validation_notification(sheet, invalid_urls) do
    message = format_validation_message(sheet, invalid_urls)

    # Group URLs by error type for better organization
    errors_by_type = group_errors_by_type(invalid_urls)

    Notifications.create_notification(%{
      category: "Google sheets",
      message: message,
      severity: Notifications.types().warning,
      organization_id: sheet.organization_id,
      entity: %{
        sheet_id: sheet.id,
        sheet_label: sheet.label,
        sheet_url: sheet.url,
        invalid_url_count: map_size(invalid_urls),
        errors_by_type: errors_by_type,
        sample_errors: Enum.take(invalid_urls, 5)
      }
    })

    :ok
  end

  @spec format_validation_message(Sheet.t(), map()) :: String.t()
  defp format_validation_message(sheet, invalid_urls) do
    count = map_size(invalid_urls)

    # Group by error type and show summary
    errors_by_type = group_errors_by_type(invalid_urls)

    error_summary =
      errors_by_type
      |> Enum.map_join("\n", fn {error_type, urls} ->
        "• #{error_type}: #{length(urls)} URL(s)"
      end)

    """
    Found #{count} invalid media URL(s) in sheet "#{sheet.label}":

    #{error_summary}

    Please review and fix these URLs to ensure messages can be sent successfully.
    """
  end

  @spec group_errors_by_type(map()) :: map()
  defp group_errors_by_type(invalid_urls) do
    invalid_urls
    |> Enum.group_by(
      fn {_url, metadata} -> metadata.error end,
      fn {url, metadata} ->
        %{
          url: url,
          row: metadata.row_key,
          column: metadata.column
        }
      end
    )
  end
end
