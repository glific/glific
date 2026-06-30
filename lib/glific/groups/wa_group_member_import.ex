defmodule Glific.Groups.WAGroupMemberImport do
  @moduledoc """
  Bulk-adds WhatsApp group members from a CSV, processed in the background.

  The CSV has a `phone` column plus an optional `name`. Each row creates the
  contact if it doesn't already exist and is then added to the WhatsApp group. A
  `UserJob` tracks progress, the CSV is chunked, and one Oban job is enqueued per
  chunk.
  """

  alias Glific.{
    Groups.WAGroupMemberImportWorker,
    Jobs.UserJob,
    Notifications
  }

  @chunk_size 100

  @doc """
  Extracts the phone numbers from a CSV string (its `phone` column). Used by the
  create flow to seed Maytapi's `createGroup` (which rejects an empty list)
  before the enrichment job runs.
  """
  @spec extract_phones(String.t()) :: [String.t()]
  def extract_phones(data) do
    data
    |> decode_csv()
    |> Stream.flat_map(fn
      {:ok, %{"phone" => phone}} when phone not in [nil, ""] -> [phone]
      _ -> []
    end)
    |> Enum.to_list()
  end

  @doc """
  Kicks off a background import of group members from a CSV.

  `opts` is exactly one of `[data: csv_string]`, `[url: url]` or
  `[file_path: path]`. Each member is added to the group via Maytapi (members
  already in the group are skipped) and their contact is created if needed.
  Returns `{:ok, %{status: ...}}` immediately — progress and per-row errors are
  tracked on the created `UserJob` (surfaced via the upload report).
  """
  @spec import_members(non_neg_integer(), non_neg_integer(), Keyword.t()) :: {:ok, map()}
  def import_members(org_id, wa_group_id, opts) do
    if length(opts) > 1 do
      raise "Please specify only one of: file_path, url or data"
    end

    user_job =
      UserJob.create_user_job(%{
        status: "pending",
        type: "wa_group_member_import",
        total_tasks: 0,
        tasks_done: 0,
        organization_id: org_id,
        errors: %{}
      })

    create_notification(org_id, user_job.id)

    params = %{"organization_id" => org_id, "wa_group_id" => wa_group_id}

    total_chunks =
      opts
      |> fetch_data_as_string()
      |> decode_csv()
      |> Stream.flat_map(fn
        {:ok, row} -> [Map.take(row, ["phone", "name"])]
        _ -> []
      end)
      |> Stream.chunk_every(@chunk_size)
      |> Stream.with_index()
      |> Enum.map(fn {chunk, index} ->
        WAGroupMemberImportWorker.make_job(chunk, params, user_job.id, index * 2)
      end)
      |> Enum.count()

    UserJob.update_user_job(user_job, %{total_tasks: total_chunks, all_tasks_created: true})

    {:ok, %{status: "WA group member import is in progress"}}
  end

  # Decode a CSV (raw string or line stream) into a stream of `{:ok, row}` /
  # `{:error, _}` tuples.
  @spec decode_csv(String.t() | Enumerable.t()) :: Enumerable.t()
  defp decode_csv(data) when is_binary(data) do
    {:ok, stream} = StringIO.open(data)

    stream
    |> IO.binstream(:line)
    |> decode_csv()
  end

  defp decode_csv(stream),
    do: CSV.decode(stream, headers: true, field_transform: &String.trim/1)

  @spec fetch_data_as_string(Keyword.t()) :: File.Stream.t() | IO.Stream.t()
  defp fetch_data_as_string(opts) do
    file_path = Keyword.get(opts, :file_path, nil)
    url = Keyword.get(opts, :url, nil)
    data = Keyword.get(opts, :data, nil)

    cond do
      file_path != nil ->
        file_path |> Path.expand() |> File.stream!()

      url != nil ->
        {:ok, response} = Tesla.get(url)
        {:ok, stream} = StringIO.open(response.body)
        stream |> IO.binstream(:line)

      data != nil ->
        {:ok, stream} = StringIO.open(data)
        stream |> IO.binstream(:line)
    end
  end

  @spec create_notification(non_neg_integer(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  defp create_notification(org_id, user_job_id) do
    Notifications.create_notification(%{
      category: "WA Group Member Upload",
      message: "WhatsApp group member upload in progress",
      severity: Notifications.types().info,
      organization_id: org_id,
      entity: %{user_job_id: user_job_id}
    })
  end
end
