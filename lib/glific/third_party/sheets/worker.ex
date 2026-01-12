defmodule Glific.Sheets.Worker do
  @moduledoc """
  Worker for Google sheet background tasks.
  """
  require Logger

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 3

  alias Glific.Messages
  alias Glific.Notifications
  alias Glific.RepoReplica
  alias Glific.Sheets.Sheet
  alias Glific.Sheets.SheetData

  import Ecto.Query

  @doc """
  Enqueue a job to validate media URLs for a given sheet.
  """
  @spec make_media_validation_job(Sheet.t()) :: {:ok, Oban.Job.t()}
  def make_media_validation_job(sheet) do
    __MODULE__.new(
      %{
        sheet_id: sheet.id,
        organization_id: sheet.organization_id
      },
      schedule_in: {10, :minutes},
      tags: [:media_validation]
    )
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: args, tags: ["media_validation"]}) do
    %{"sheet_id" => sheet_id, "organization_id" => organization_id} = args
    RepoReplica.put_process_state(organization_id)

    Logger.info("Starting media validation for sheet_id: #{sheet_id}")

    # Get all sheet_data rows for this sheet
    sheet_data_rows =
      SheetData
      |> where([sd], sd.sheet_id == ^sheet_id)
      |> RepoReplica.all()

    # Validate all media URLs and collect warnings
    media_warnings =
      sheet_data_rows
      |> Enum.reduce(%{}, fn sheet_data, acc ->
        warnings = validate_media_values(sheet_data)
        Map.merge(acc, warnings)
      end)

    if map_size(media_warnings) > 0 do
      Logger.warning(
        "Media validation found #{map_size(media_warnings)} warnings for sheet_id: #{sheet_id}"
      )

      create_media_validation_failed_notification(sheet_id, media_warnings)
    end

    Logger.info("Media validation completed for sheet_id: #{sheet_id}")

    :ok
  end

  @spec validate_media_values(map()) :: map()
  defp validate_media_values(sheet_data) do
    sheet_data.row_data
    |> Enum.reduce(%{}, fn {_key, value}, acc ->
      {media_type, _media} = Messages.get_media_type_from_url(value, log_error: false)

      with true <- media_type != :text,
           %{is_valid: is_valid, message: message} <-
             Messages.validate_media(value, Atom.to_string(media_type)),
           false <- is_valid do
        Map.put(acc, sheet_data.key, %{value => message})
      else
        _ -> acc
      end
    end)
  end

  defp create_media_validation_failed_notification(sheet_id, media_warnings) do
    {:ok, sheet} = RepoReplica.fetch(Sheet, sheet_id)

    Notifications.create_notification(%{
      category: "Google sheets",
      message: "Google sheet media validation failed",
      severity: Notifications.types().warning,
      organization_id: sheet.organization_id,
      entity: %{
        url: sheet.url,
        id: sheet.id,
        name: sheet.label,
        media_validation_warnings: media_warnings
      }
    })
  end
end
