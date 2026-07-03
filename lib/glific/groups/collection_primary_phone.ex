defmodule Glific.Groups.CollectionPrimaryPhone do
  @moduledoc """
  Bulk "primary-on-collection": set a single managed phone as the primary for
  every WhatsApp group in a Glific collection, in one admin action.

  The work runs in the background (`CollectionPrimaryPhoneWorker`, one Oban job
  per request) because a collection can hold many groups; a `UserJob` tracks it
  and the existing completion cron fires a single notification when it's done.
  Per group the chosen phone is *skipped* (not promoted) when it isn't a member,
  its membership is inactive, or the phone's Maytapi status is unhealthy — those
  skips are collected into the `UserJob` and surfaced to the admin as a CSV.
  Groups where the phone is already primary are silent no-ops.
  """

  require Logger
  import Ecto.Query

  alias Glific.{
    Groups.CollectionPrimaryPhoneWorker,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Groups.WAGroupsCollection,
    Jobs.UserJob,
    Repo,
    SafeLog,
    WAGroup.WAManagedPhone
  }

  @job_type "collection_primary_phone"

  @doc """
  The `UserJob.type` used for this job, so the completion notification and the
  report resolver can recognise it.
  """
  @spec job_type() :: String.t()
  def job_type, do: @job_type

  @doc """
  Entry point for the `setPrimaryPhoneForCollection` mutation (scoped to `org_id`).

  Validates synchronously that the phone exists and is a member of at least one
  WhatsApp group in the collection — if it's a member of *none*, returns
  `{:error, message}` immediately so the UI can surface the no-op prominently
  (nothing is enqueued). Otherwise creates a `UserJob`, enqueues the background
  worker, and returns `{:ok, %{status, user_job_id}}`.
  """
  @spec set_primary_phone_for_collection(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, %{status: String.t(), user_job_id: non_neg_integer()}} | {:error, String.t()}
  def set_primary_phone_for_collection(org_id, collection_id, wa_managed_phone_id) do
    with {:ok, _phone} <- validate_phone(org_id, wa_managed_phone_id),
         wa_group_ids when wa_group_ids != [] <- collection_wa_group_ids(org_id, collection_id),
         true <- member_of_any?(org_id, wa_managed_phone_id, wa_group_ids) do
      enqueue(org_id, collection_id, wa_managed_phone_id)
    else
      {:error, reason} ->
        {:error, reason}

      [] ->
        {:error, "This collection has no WhatsApp groups."}

      false ->
        {:error,
         "This phone is not a member of any WhatsApp group in this collection. Add it to a group on WhatsApp first."}
    end
  end

  # Create the tracking UserJob and enqueue the worker. If the enqueue (or the
  # follow-up flag update) fails, mark the job failed so it doesn't hang "pending"
  # forever and surface the error instead of falsely reporting "started".
  @spec enqueue(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, %{status: String.t(), user_job_id: non_neg_integer()}} | {:error, String.t()}
  defp enqueue(org_id, collection_id, wa_managed_phone_id) do
    user_job =
      UserJob.create_user_job(%{
        status: "pending",
        type: @job_type,
        total_tasks: 1,
        tasks_done: 0,
        all_tasks_created: false,
        organization_id: org_id,
        errors: %{}
      })

    with {:ok, _job} <-
           CollectionPrimaryPhoneWorker.make_job(
             org_id,
             collection_id,
             wa_managed_phone_id,
             user_job.id
           ),
         {:ok, _user_job} <- UserJob.update_user_job(user_job, %{all_tasks_created: true}) do
      {:ok,
       %{
         status:
           "Setting the primary phone across the collection id #{collection_id} has started in the background.",
         user_job_id: user_job.id
       }}
    else
      error ->
        UserJob.update_user_job(user_job, %{status: "failed", all_tasks_created: true})

        Glific.log_error(
          "Collection primary-phone: could not start job for collection #{collection_id}: #{SafeLog.safe_inspect(error)}"
        )

        {:error, "Could not start the collection primary-phone update. Please try again."}
    end
  end

  @doc """
  Runs the bulk promotion for one collection. Called by
  `CollectionPrimaryPhoneWorker`. Iterates the collection's WhatsApp groups,
  promotes the phone to primary where valid, and records the skipped groups (with
  a reason each) against `user_job_id`.
  """
  @spec process(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def process(org_id, collection_id, wa_managed_phone_id, user_job_id) do
    phone_healthy? = phone_healthy?(org_id, wa_managed_phone_id)

    {skipped, promoted} =
      collection_id
      |> collection_wa_groups(org_id)
      |> Enum.reduce({%{}, 0}, fn {wa_group_id, label}, {skips, promoted} ->
        case classify_and_promote(wa_group_id, wa_managed_phone_id, phone_healthy?) do
          :promoted -> {skips, promoted + 1}
          :noop -> {skips, promoted}
          {:skipped, reason} -> {Map.put(skips, group_key(wa_group_id, label), reason), promoted}
        end
      end)

    Logger.info(
      "Collection primary-phone done: collection=#{collection_id} phone=#{wa_managed_phone_id} " <>
        "promoted=#{promoted} skipped=#{map_size(skipped)}"
    )

    record_result(user_job_id, skipped)
    :ok
  end

  @doc """
  Fetches the skip report (scoped to `org_id`) for a completed collection
  primary-phone job as CSV rows (`Group,Reason`). Mirrors the contact-upload
  report. `params` must contain `:user_job_id`.
  """
  @spec get_report(non_neg_integer(), map()) :: {:ok, map()}
  def get_report(org_id, params) do
    Repo.put_process_state(org_id)

    case UserJob.list_user_jobs(%{filter: %{id: params.user_job_id}}) do
      [%UserJob{status: "success", type: @job_type} = user_job] ->
        skipped = user_job.errors["errors"] || %{}

        csv_rows =
          [["Group", "Reason"] | Enum.map(skipped, fn {group, reason} -> [group, reason] end)]
          |> CSV.encode()
          |> Enum.join()

        {:ok, %{csv_rows: csv_rows}}

      [%UserJob{type: @job_type}] ->
        {:ok, %{error: "Setting the primary phone across the collection is still in progress."}}

      _ ->
        {:ok, %{error: "This collection primary-phone report doesn't exist."}}
    end
  end

  @spec validate_phone(non_neg_integer(), non_neg_integer()) ::
          {:ok, WAManagedPhone.t()} | {:error, String.t()}
  defp validate_phone(org_id, wa_managed_phone_id) do
    case Repo.get_by(WAManagedPhone, %{id: wa_managed_phone_id, organization_id: org_id}) do
      nil -> {:error, "The selected WhatsApp phone was not found."}
      phone -> {:ok, phone}
    end
  end

  @spec phone_healthy?(non_neg_integer(), non_neg_integer()) :: boolean()
  defp phone_healthy?(org_id, wa_managed_phone_id) do
    case Repo.get_by(WAManagedPhone, %{id: wa_managed_phone_id, organization_id: org_id}) do
      %WAManagedPhone{status: "active"} -> true
      _ -> false
    end
  end

  @spec collection_wa_group_ids(non_neg_integer(), non_neg_integer()) :: [non_neg_integer()]
  defp collection_wa_group_ids(org_id, collection_id) do
    collection_id
    |> collection_wa_groups(org_id)
    |> Enum.map(fn {wa_group_id, _label} -> wa_group_id end)
  end

  @spec collection_wa_groups(non_neg_integer(), non_neg_integer()) ::
          [{non_neg_integer(), String.t() | nil}]
  defp collection_wa_groups(collection_id, org_id) do
    WAGroupsCollection
    |> where([wgc], wgc.group_id == ^collection_id and wgc.organization_id == ^org_id)
    |> join(:inner, [wgc], wg in WAGroup, on: wg.id == wgc.wa_group_id)
    |> select([_wgc, wg], {wg.id, wg.label})
    |> Repo.all()
  end

  @spec member_of_any?(non_neg_integer(), non_neg_integer(), [non_neg_integer()]) :: boolean()
  defp member_of_any?(org_id, wa_managed_phone_id, wa_group_ids) do
    WAGroupPhone
    |> where(
      [wgp],
      wgp.organization_id == ^org_id and wgp.wa_managed_phone_id == ^wa_managed_phone_id and
        wgp.wa_group_id in ^wa_group_ids
    )
    |> Repo.exists?()
  end

  # Classify one group and, when valid, promote the phone by reusing the tested
  # per-group `WAGroups.set_primary_phone/2` (demote-then-promote in a
  # transaction). Membership is checked before phone health so groups the phone
  # isn't in report the more specific `not_a_member` rather than a health issue.
  @spec classify_and_promote(non_neg_integer(), non_neg_integer(), boolean()) ::
          :promoted | :noop | {:skipped, String.t()}
  defp classify_and_promote(wa_group_id, wa_managed_phone_id, phone_healthy?) do
    case Repo.get_by(WAGroupPhone, %{
           wa_group_id: wa_group_id,
           wa_managed_phone_id: wa_managed_phone_id
         }) do
      nil ->
        {:skipped, "not_a_member"}

      %WAGroupPhone{is_active: false} ->
        {:skipped, "member_inactive"}

      %WAGroupPhone{is_primary: true} ->
        :noop

      %WAGroupPhone{} ->
        promote(wa_group_id, wa_managed_phone_id, phone_healthy?)
    end
  end

  @spec promote(non_neg_integer(), non_neg_integer(), boolean()) ::
          :promoted | {:skipped, String.t()}
  defp promote(_wa_group_id, _wa_managed_phone_id, false),
    do: {:skipped, "phone_status_unhealthy"}

  defp promote(wa_group_id, wa_managed_phone_id, true) do
    case WAGroups.set_primary_phone(wa_group_id, wa_managed_phone_id) do
      {:ok, _result} ->
        Appsignal.increment_counter("glific.maytapi.primary_changed", 1, %{source: "collection"})
        :promoted

      {:error, :membership_not_found} ->
        {:skipped, "not_a_member"}

      {:error, :inactive_membership} ->
        {:skipped, "member_inactive"}

      {:error, _reason} ->
        {:skipped, "error"}
    end
  end

  # Stable, unique CSV key per group (labels can collide, ids can't).
  @spec group_key(non_neg_integer(), String.t() | nil) :: String.t()
  defp group_key(wa_group_id, label) do
    "#{label || "WA Group"} (##{wa_group_id})"
  end

  @spec record_result(non_neg_integer(), map()) :: :ok
  defp record_result(user_job_id, skipped) do
    case Repo.fetch_by(UserJob, %{id: user_job_id}) do
      {:ok, user_job} ->
        UserJob.update_user_job(user_job, %{
          tasks_done: user_job.total_tasks,
          errors: %{"errors" => skipped}
        })

      {:error, _reason} ->
        Glific.log_error(
          "Collection primary-phone: user_job #{user_job_id} not found while recording result"
        )
    end

    :ok
  end
end
