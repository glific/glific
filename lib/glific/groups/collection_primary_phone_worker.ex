defmodule Glific.Groups.CollectionPrimaryPhoneWorker do
  @moduledoc """
  Oban worker that runs one bulk "primary-on-collection" request: set a chosen
  managed phone as primary across every WhatsApp group in a collection.

  The whole collection is handled in a single job (the per-group work is a local
  DB transaction, no Maytapi calls), delegating to
  `Glific.Groups.CollectionPrimaryPhone.process/4`, which records skipped groups
  against the tracking `UserJob`. Completion + the admin notification are handled
  by the existing `UserJobWorker` cron.
  """

  use Oban.Worker,
    queue: :wa_group,
    max_attempts: 2,
    priority: 1

  alias Glific.{
    Groups.CollectionPrimaryPhone,
    Repo
  }

  @doc """
  Enqueue the job for one collection primary-phone request.
  """
  @spec make_job(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def make_job(org_id, collection_id, wa_managed_phone_id, user_job_id) do
    __MODULE__.new(%{
      organization_id: org_id,
      collection_id: collection_id,
      wa_managed_phone_id: wa_managed_phone_id,
      user_job_id: user_job_id
    })
    |> Oban.insert()
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{
        args: %{
          "organization_id" => org_id,
          "collection_id" => collection_id,
          "wa_managed_phone_id" => wa_managed_phone_id,
          "user_job_id" => user_job_id
        }
      }) do
    Repo.put_process_state(org_id)
    CollectionPrimaryPhone.process(org_id, collection_id, wa_managed_phone_id, user_job_id)
  end
end
