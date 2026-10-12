defmodule Glific.Contacts.IdentityBackfillWorker do
  @moduledoc """
  Gives every existing contact with a phone its `(whatsapp, phone)` identity.

  A deliberate cross-organization admin job, so it never restores a tenant: it walks all contacts
  by id in chunks, inserts the missing identities, and enqueues the next chunk from the last id.
  Re-running it is harmless and it resumes from where a failed chunk stopped.

  Start it from the remote IEx console (e.g. `gigalixir remote_console`):

      Glific.Contacts.IdentityBackfillWorker.start()

  or resume after a given contact id:

      Glific.Contacts.IdentityBackfillWorker.start(after_id)
  """

  use Oban.Worker, queue: :purge, max_attempts: 3

  import Ecto.Query

  alias Glific.{Contacts.Contact, Contacts.Identities, Repo}

  @chunk_size 1_000

  @doc """
  Enqueues the backfill, from the first contact unless given the id to continue after.
  """
  @spec start(non_neg_integer()) :: {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset() | term()}
  def start(after_id \\ 0), do: enqueue(after_id)

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"after_id" => after_id}}) do
    rows =
      from(c in Contact,
        where: c.id > ^after_id,
        order_by: c.id,
        limit: @chunk_size,
        select: %{id: c.id, phone: c.phone, organization_id: c.organization_id}
      )
      |> Repo.all(skip_organization_id: true)

    Identities.insert_whatsapp_identities(rows)

    with %{id: last_id} <- List.last(rows),
         {:ok, _job} <- enqueue(last_id) do
      :ok
    else
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec enqueue(non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset() | term()}
  defp enqueue(after_id), do: %{after_id: after_id} |> new() |> Oban.insert()
end
