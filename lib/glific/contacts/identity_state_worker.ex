defmodule Glific.Contacts.IdentityStateWorker do
  @moduledoc """
  One link of the chain `Glific.Contacts.IdentityStateBackfill.start/1` begins: copies one chunk of
  contacts (ids above `after_id`, at most `batch_size`) onto their WhatsApp identities, then enqueues
  the link for the next chunk, `pause` seconds later. The chunk that finds fewer contacts than
  `batch_size` ends the chain with `ANALYZE contact_identities`.

  It runs on `:purge`, which has a limit of one, and is unique while any link is queued or running, so
  there is never more than one chain. It deliberately covers every organization, so it never restores
  an organization context. A link that fails is retried on its own chunk, which is safe to repeat.
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

  alias Glific.Contacts.IdentityStateBackfill

  @default_pause 1

  @doc """
  The defaults of a chain, as the job args `IdentityStateBackfill.start/1` merges its options into.
  """
  @spec default_args() :: map()
  def default_args,
    do: %{
      after_id: 0,
      batch_size: IdentityStateBackfill.default_batch_size(),
      pause: @default_pause
    }

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, any()}
  def perform(%Oban.Job{args: args} = job) do
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
      true -> enqueue_next(args, last_id)
    end
  end

  @spec finish() :: :ok
  defp finish do
    IdentityStateBackfill.analyze()
    Appsignal.Logger.info("contact_identity_state", "Finished copying contact state")
  end

  @spec enqueue_next(map(), non_neg_integer()) :: :ok | {:error, any()}
  defp enqueue_next(args, last_id) do
    # The running job still holds the uniqueness slot, so the next link must opt out of it.
    args
    |> Map.put("after_id", last_id)
    |> new(schedule_in: Map.get(args, "pause", @default_pause), unique: false)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Cancelling a running job does not stop it, so a stop is only seen by reading the job back.
  @spec cancelled?(Oban.Job.t()) :: boolean()
  defp cancelled?(%Oban.Job{id: nil}), do: false

  defp cancelled?(%Oban.Job{id: id}) do
    query = from(j in Oban.Job, where: j.id == ^id and j.state == "cancelled")
    Oban.Repo.exists?(Oban.config(), query)
  end
end
