defmodule Glific.Scripts.BigQueryTieDemo do
  @moduledoc """
  Local demonstration of the BigQuery update-sync row bound (issue #5468).

  Creates contacts that all share one `updated_at` — the situation a bulk
  `Repo.update_all/3` produces — then shows how many rows a single sync run pulls out of
  Postgres under the old timestamp-only bookmark versus the current `(updated_at, id)` one.

  Needs no BigQuery credentials: the fix is entirely about the size of the Postgres read,
  so nothing is sent anywhere.

  Must run under `MIX_ENV=test`. `BigQueryWorker` reaches its query internals through
  `use Publicist`, which only rewrites `defp` when `Mix.env == :test` — in `:dev` those
  functions are genuinely private and this module cannot call them.

      MIX_ENV=test iex -S mix

      alias Glific.Scripts.BigQueryTieDemo, as: Demo

      # 1. create 1000 contacts all stamped with the same updated_at
      since = Demo.seed(1, 1000)

      # 2. old bookmark vs new bookmark on identical data
      Demo.compare(1, since)

      # 3. walk every sync run until the backlog is drained
      Demo.drain(1, since)

      # 4. remove the demo contacts
      Demo.cleanup(1)

  Every contact created here uses the phone prefix `5550` so `cleanup/1` can delete exactly
  what was added and nothing else.
  """

  import Ecto.Query

  require Logger

  alias Glific.{
    BigQuery.BigQueryWorker,
    Contacts.Contact,
    Repo,
    RepoReplica
  }

  @phone_prefix "5550"

  @doc """
  Inserts `count` contacts sharing one `updated_at`. Returns the bookmark to sync from.
  """
  @spec seed(non_neg_integer, pos_integer) :: DateTime.t()
  def seed(organization_id, count \\ 1000) do
    put_org_context(organization_id)

    tied_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    # updated_at has to sit a few seconds past inserted_at: the sync filters on the seconds
    # component of age(updated_at, inserted_at), so a sub-second gap is skipped entirely.
    inserted_at = DateTime.add(tied_at, -10, :second)

    rows =
      Enum.map(1..count, fn n ->
        %{
          name: "Tie Demo #{n}",
          phone: "#{@phone_prefix}#{String.pad_leading(to_string(n), 7, "0")}",
          language_id: 1,
          organization_id: organization_id,
          inserted_at: inserted_at,
          updated_at: tied_at
        }
      end)

    {inserted, _} =
      rows
      |> Enum.chunk_every(500)
      |> Enum.reduce({0, nil}, fn chunk, {total, _} ->
        {n, _} = Repo.insert_all(Contact, chunk, on_conflict: :nothing)
        {total + n, nil}
      end)

    IO.puts("""

    Inserted #{inserted} contacts, all with updated_at = #{tied_at}
    Sync bookmark for the demo: #{DateTime.add(tied_at, -1, :second)}
    """)

    DateTime.add(tied_at, -1, :second)
  end

  @doc """
  Prints how many rows one sync run reads, under the old bookmark and the current one.
  """
  @spec compare(non_neg_integer, DateTime.t()) :: :ok
  def compare(organization_id, since) do
    put_org_context(organization_id)

    limit = Application.get_env(:glific, :bigquery_per_min_limit, 500)

    case BigQueryWorker.insert_last_updated("contacts", since, 0, organization_id) do
      nil ->
        IO.puts("\nNothing to sync since #{since}. Run seed/2 first.\n")

      cursor ->
        new_rows = length(fetch_new(organization_id, since, 0, cursor))
        old_rows = count_old(organization_id, since, cursor.updated_at)

        IO.puts("""

        Rows in one sync run — limit is #{limit}

          old bookmark  updated_at <= #{cursor.updated_at}
                        #{old_rows} rows loaded into memory
                        (every row tied on that timestamp, the limit is not expressible)

          new bookmark  (updated_at, id) <= (#{cursor.updated_at}, #{cursor.id})
                        #{new_rows} rows loaded into memory

          reduction     #{old_rows} -> #{new_rows}#{over_limit_note(old_rows, limit)}
        """)
    end

    :ok
  end

  @doc """
  Walks sync runs from `since` until the backlog is drained, printing each run.
  """
  @spec drain(non_neg_integer, DateTime.t()) :: :ok
  def drain(organization_id, since) do
    put_org_context(organization_id)
    limit = Application.get_env(:glific, :bigquery_per_min_limit, 500)

    IO.puts("\nDraining from #{since} with a limit of #{limit} per run\n")
    do_drain(organization_id, since, 0, 1, 0)
  end

  @doc """
  Deletes every contact `seed/2` created, matched on the demo phone prefix.
  """
  @spec cleanup(non_neg_integer) :: :ok
  def cleanup(organization_id) do
    put_org_context(organization_id)

    {deleted, _} =
      Contact
      |> where([c], like(c.phone, ^"#{@phone_prefix}%"))
      |> where([c], c.organization_id == ^organization_id)
      |> Repo.delete_all()

    IO.puts("\nDeleted #{deleted} demo contacts\n")
    :ok
  end

  @spec do_drain(non_neg_integer, DateTime.t(), non_neg_integer, pos_integer, non_neg_integer) ::
          :ok
  defp do_drain(_organization_id, _since, _since_id, run, total) when run > 50 do
    IO.puts("Stopped after 50 runs (#{total} rows) — bookmark is not advancing.")
  end

  defp do_drain(organization_id, since, since_id, run, total) do
    case BigQueryWorker.insert_last_updated("contacts", since, since_id, organization_id) do
      nil ->
        IO.puts("\nDrained: #{total} rows over #{run - 1} sync runs, nothing left.\n")

      cursor ->
        rows = fetch_new(organization_id, since, since_id, cursor)
        ids = Enum.map(rows, & &1.id)

        IO.puts(
          "run #{String.pad_leading(to_string(run), 2)}  " <>
            "#{String.pad_leading(to_string(length(rows)), 4)} rows  " <>
            "ids #{List.first(ids)}..#{List.last(ids)}  " <>
            "-> bookmark id #{cursor.id}"
        )

        do_drain(organization_id, cursor.updated_at, cursor.id, run + 1, total + length(rows))
    end
  end

  @spec fetch_new(non_neg_integer, DateTime.t(), non_neg_integer, map()) :: list()
  defp fetch_new(organization_id, since, since_id, cursor) do
    BigQueryWorker.fetch_data("contacts", organization_id, %{
      action: :update,
      last_updated_at: cursor.updated_at,
      last_updated_id: cursor.id,
      table_last_updated_at: since,
      table_last_updated_id: since_id
    })
  end

  @spec count_old(non_neg_integer, DateTime.t(), DateTime.t()) :: non_neg_integer
  defp count_old(organization_id, since, cursor_updated_at) do
    Contact
    |> where([c], c.organization_id == ^organization_id)
    |> where([c], c.updated_at > ^since and c.updated_at <= ^cursor_updated_at)
    |> where(
      [c],
      fragment("DATE_PART('seconds', age(?, ?))::integer", c.updated_at, c.inserted_at) > 0
    )
    |> RepoReplica.aggregate(:count, :id)
  end

  @spec over_limit_note(non_neg_integer, pos_integer) :: String.t()
  defp over_limit_note(old_rows, limit) when old_rows > limit,
    do: "  (old path was #{Float.round(old_rows / limit, 1)}x over the limit)"

  defp over_limit_note(_old_rows, _limit), do: ""

  @spec put_org_context(non_neg_integer) :: :ok
  defp put_org_context(organization_id) do
    Repo.put_process_state(organization_id)
    RepoReplica.put_process_state(organization_id)
    :ok
  end
end
