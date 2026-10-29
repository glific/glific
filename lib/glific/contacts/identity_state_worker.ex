defmodule Glific.Contacts.IdentityStateWorker do
  @moduledoc """
  One link of the chain `Glific.Contacts.IdentityStateBackfill.start/1` begins: copies one chunk of
  contacts (ids above `after_id`, at most `batch_size`) onto their WhatsApp identities, then enqueues
  the link for the next chunk, `pause` seconds later. The chunk that finds fewer contacts than
  `batch_size` ends the chain with `ANALYZE contact_identities`.

  It runs on `:purge`, which has a limit of one, and is unique while any link is queued or running, so
  there is never more than one chain. It deliberately covers every organization, so it never restores
  an organization context. A link that fails is retried on its own chunk, which is safe to repeat; one
  that fails its last attempt is logged as an error with the id to resume from.
  """

  use Oban.Worker,
    queue: :purge,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query

  alias Glific.{Contacts.IdentityStateBackfill, SafeLog}

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, any()}
  def perform(%Oban.Job{} = job) do
    case copy_and_chain(job) do
      {:error, reason} = error ->
        log_if_last_attempt(job, SafeLog.safe_inspect(reason))
        error

      :ok ->
        :ok
    end
  rescue
    exception ->
      log_if_last_attempt(job, Exception.message(exception))
      reraise exception, __STACKTRACE__
  end

  @spec copy_and_chain(Oban.Job.t()) :: :ok | {:error, any()}
  defp copy_and_chain(%Oban.Job{args: args} = job) do
    after_id = Map.fetch!(args, "after_id")
    batch_size = Map.fetch!(args, "batch_size")

    %{scanned: scanned, last_id: last_id} =
      chunk = IdentityStateBackfill.copy_chunk(after_id, batch_size)

    Appsignal.Logger.info(
      "contact_identity_state",
      "Reached contact #{last_id}: scanned #{scanned}, inserted #{chunk.inserted}, updated #{chunk.updated}"
    )

    cond do
      scanned < batch_size -> finish()
      cancelled?(job) -> :ok
      true -> enqueue_next(job, last_id)
    end
  end

  @spec finish() :: :ok
  defp finish do
    IdentityStateBackfill.analyze()
    Appsignal.Logger.info("contact_identity_state", "Finished copying contact state")
  end

  # A link retried after its node died may already have enqueued its next one; a second would fork the chain.
  @spec enqueue_next(Oban.Job.t(), non_neg_integer()) :: :ok | {:error, any()}
  defp enqueue_next(%Oban.Job{id: id, args: args}, last_id) do
    if IdentityStateBackfill.another_link?(id),
      do: :ok,
      else: insert_next(args, last_id)
  end

  @spec insert_next(map(), non_neg_integer()) :: :ok | {:error, any()}
  defp insert_next(args, last_id) do
    # The running job still holds the uniqueness slot, so the next link must opt out of it.
    args
    |> Map.put("after_id", last_id)
    |> new(schedule_in: Map.fetch!(args, "pause"), unique: false)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A stop that lands just as the chunk finishes misses Oban's kill, so the job is read back before chaining.
  @spec cancelled?(Oban.Job.t()) :: boolean()
  defp cancelled?(%Oban.Job{id: nil}), do: false

  defp cancelled?(%Oban.Job{id: id}) do
    query = from(j in Oban.Job, where: j.id == ^id and j.state == "cancelled")
    Oban.Repo.exists?(Oban.config(), query)
  end

  @spec log_if_last_attempt(Oban.Job.t(), String.t()) :: :ok
  defp log_if_last_attempt(%Oban.Job{attempt: attempt, max_attempts: max} = job, reason)
       when attempt >= max do
    Glific.log_error(
      "Contact identity state copy gave up after #{attempt} attempts; " <>
        "resume with start(after_id: #{job.args["after_id"]}): #{reason}"
    )

    :ok
  end

  defp log_if_last_attempt(_job, _reason), do: :ok
end
