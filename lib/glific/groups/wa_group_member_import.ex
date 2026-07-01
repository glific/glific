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
  @chunk_stagger_seconds 2

  @doc """
  Lazily extracts the phone numbers from a CSV string (its `phone` column) as a
  `Stream`. Used by the create flow to seed Maytapi's `createGroup` (which
  rejects an empty list) — it only needs the first phone, so the stream lets
  `Enum.take(1)` stop after the first row instead of parsing the whole file.
  """
  @spec extract_phones(String.t()) :: Enumerable.t()
  def extract_phones(data) do
    data
    |> decode_csv()
    |> Stream.flat_map(fn
      {:ok, %{"phone" => phone}} when phone not in [nil, ""] -> [phone]
      _ -> []
    end)
  end

  @doc """
  Kicks off a background import of group members from a CSV.

  `opts` is exactly one of `[data: csv_string]`, `[url: url]` or
  `[file_path: path]`. Each member is added to the group via Maytapi (members
  already in the group are skipped) and their contact is created if needed.
  Returns `{:ok, %{status: ...}}` immediately — progress and per-row errors are
  tracked on the created `UserJob` (surfaced via the upload report).
  """
  @spec import_members(non_neg_integer(), non_neg_integer(), Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def import_members(org_id, wa_group_id, opts) do
    case Keyword.take(opts, [:file_path, :url, :data]) do
      [{_source, value}] when value not in [nil, ""] ->
        run_import(org_id, wa_group_id, opts)

      _ ->
        {:error, "Please specify exactly one of: file_path, url or data"}
    end
  end

  @spec run_import(non_neg_integer(), non_neg_integer(), Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp run_import(org_id, wa_group_id, opts) do
    # Resolve the source first so a failed download doesn't leave an orphan job.
    with {:ok, stream} <- fetch_data_as_string(opts) do
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
        stream
        |> decode_csv()
        |> Stream.flat_map(fn
          {:ok, row} -> [Map.take(row, ["phone", "name"])]
          _ -> []
        end)
        |> Stream.chunk_every(@chunk_size)
        |> Stream.with_index()
        |> Enum.map(fn {chunk, index} ->
          WAGroupMemberImportWorker.make_job(
            chunk,
            params,
            user_job.id,
            index * @chunk_stagger_seconds
          )
        end)
        |> Enum.count()

      UserJob.update_user_job(user_job, %{total_tasks: total_chunks, all_tasks_created: true})

      {:ok, %{status: "WA group member import is in progress"}}
    end
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

  @spec fetch_data_as_string(Keyword.t()) :: {:ok, Enumerable.t()} | {:error, String.t()}
  defp fetch_data_as_string(opts) do
    file_path = Keyword.get(opts, :file_path)
    url = Keyword.get(opts, :url)
    data = Keyword.get(opts, :data)

    cond do
      file_path != nil -> {:ok, file_path |> Path.expand() |> File.stream!()}
      url != nil -> fetch_url(url)
      data != nil -> {:ok, string_stream(data)}
    end
  end

  # Download the CSV, handling failures instead of raising — this runs
  # synchronously from the resolver, so a flaky URL must not become a 500.
  @spec fetch_url(String.t()) :: {:ok, Enumerable.t()} | {:error, String.t()}
  defp fetch_url(url) do
    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, string_stream(body)}
      _ -> {:error, "Could not download the member CSV from the given URL."}
    end
  end

  @spec string_stream(String.t()) :: Enumerable.t()
  defp string_stream(data) do
    {:ok, stream} = StringIO.open(data)
    IO.binstream(stream, :line)
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
