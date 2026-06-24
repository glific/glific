defmodule Glific.Groups.WAGroupMemberImportWorker do
  @moduledoc """
  Oban worker that processes one CSV chunk for a WhatsApp-group member import.

  For each row it creates the contact if it doesn't already exist (matching on
  phone, applying the optional `name`) via `Glific.Contacts.maybe_create_contact/1`
  and then adds the chunk's phones to the WhatsApp group. Per-row errors are merged
  into the tracking `UserJob` under `"errors"`, so the existing upload report
  renders them.
  """

  use Oban.Worker,
    queue: :wa_group,
    max_attempts: 2,
    priority: 1

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Groups.ContactWAGroup,
    Groups.WAGroup,
    Groups.WAGroups,
    Jobs.UserJob,
    Repo,
    SafeLog
  }

  @doc """
  Enqueue a job for one chunk of CSV rows (each a `%{"phone" => ..., "name" => ...}`).
  """
  @spec make_job([map()], map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def make_job(chunk, params, user_job_id, delay) do
    __MODULE__.new(%{contacts: chunk, params: params, user_job_id: user_job_id},
      schedule_in: delay
    )
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"contacts" => contacts, "params" => params, "user_job_id" => user_job_id}
      }) do
    org_id = params["organization_id"]
    wa_group_id = params["wa_group_id"]

    Repo.put_process_state(org_id)

    {contact_errors, valid_phones} = upsert_contacts(contacts, org_id)

    add_errors = add_to_wa_group(wa_group_id, valid_phones)

    record_errors(user_job_id, Map.merge(contact_errors, add_errors))

    :ok
  end

  # Create the contact for each row (idempotent upsert by phone, name applied when
  # present), collecting the normalised phones and any per-row errors.
  @spec upsert_contacts([map()], non_neg_integer()) :: {map(), [String.t()]}
  defp upsert_contacts(rows, org_id) do
    Enum.reduce(rows, {%{}, []}, fn row, {errors, phones} ->
      case upsert_contact(row, org_id) do
        {:ok, phone} -> {errors, [phone | phones]}
        {:error, error} -> {Map.merge(errors, error), phones}
      end
    end)
  end

  # Normalise the phone, then create/find the contact. Each failure becomes a
  # `%{phone => reason}` error entry for the report: a bad number reports the
  # parser's message, a rejected changeset reports a generic message.
  @spec upsert_contact(map(), non_neg_integer()) :: {:ok, String.t()} | {:error, map()}
  defp upsert_contact(%{"phone" => phone}, _org_id) when phone in [nil, ""],
    do: {:error, %{"phone" => "Phone number is missing."}}

  defp upsert_contact(%{"phone" => phone} = row, org_id) do
    with {:ok, clean_phone} <- Contacts.parse_phone_number(phone),
         {:ok, _contact} <- Contacts.maybe_create_contact(contact_attrs(clean_phone, row, org_id)) do
      {:ok, clean_phone}
    else
      {:error, %Ecto.Changeset{}} -> {:error, %{phone => "Could not create the contact"}}
      {:error, message} -> {:error, %{phone => message}}
    end
  end

  defp upsert_contact(_, _org_id), do: {:error, %{"error" => "Failed to parse some rows"}}

  # Build the contact attrs, only including `name` when the CSV row supplies one
  @spec contact_attrs(String.t(), map(), non_neg_integer()) :: map()
  defp contact_attrs(phone, row, org_id) do
    attrs = %{phone: phone, organization_id: org_id, contact_type: "WA"}

    case row["name"] do
      name when name in [nil, ""] -> attrs
      name -> Map.put(attrs, :name, name)
    end
  end

  # Add the chunk's phones to the WhatsApp group (Maytapi + membership rows),
  # skipping any that are already members — so the phone the group was created
  # with isn't re-added, and re-running the import is idempotent.
  #
  # Maytapi adds one number per call, so a single bad number only fails itself:
  # those per-number failures come back in `failed` and are recorded against the
  # job. A `{:error, _}` here is instead structural (e.g. no admin phone usable),
  # which fails every pending number, so we stamp all of them.
  @spec add_to_wa_group(non_neg_integer(), [String.t()]) :: map()
  defp add_to_wa_group(_wa_group_id, []), do: %{}

  defp add_to_wa_group(wa_group_id, phones) do
    case phones -- existing_member_phones(wa_group_id) do
      [] ->
        %{}

      new_phones ->
        # The worker's process-state org (set in perform/1) scopes this lookup.
        with {:ok, wa_group} <-
               Repo.fetch_by(WAGroup, %{id: wa_group_id}),
             {:ok, _wa_group, failed} <-
               WAGroups.update_wa_group_via_maytapi(wa_group, %{add_phones: new_phones}) do
          report_failed_adds(wa_group_id, failed)
        else
          {:error, reason} ->
            Glific.log_error(
              "WA group member import: add to group failed — wa_group=#{wa_group_id} reason=#{SafeLog.safe_inspect(reason)}"
            )

            Map.new(new_phones, fn phone ->
              {phone, "Could not be added to the WhatsApp group"}
            end)
        end
    end
  end

  # Map each Maytapi-rejected number to a clear, member-scoped status for the
  # report (the raw reasons are logged for debugging).
  @spec report_failed_adds(non_neg_integer(), %{String.t() => String.t()}) :: map()
  defp report_failed_adds(_wa_group_id, failed) when failed == %{}, do: %{}

  defp report_failed_adds(wa_group_id, failed) do
    Glific.log_error(
      "WA group member import: some numbers could not be added — wa_group=#{wa_group_id} failures=#{SafeLog.safe_inspect(failed)}"
    )

    Map.new(failed, fn {phone, _message} -> {phone, "Could not be added to the WhatsApp group"} end)
  end

  @spec existing_member_phones(non_neg_integer()) :: [String.t()]
  defp existing_member_phones(wa_group_id) do
    ContactWAGroup
    |> where([cwg], cwg.wa_group_id == ^wa_group_id)
    |> join(:inner, [cwg], c in Contact, on: c.id == cwg.contact_id)
    |> select([_cwg, c], c.phone)
    |> Repo.all()
  end

  # Accumulate this chunk's errors under the "errors" key (deep-merge so earlier
  # chunks aren't overwritten), matching the contact-upload report shape.
  @spec record_errors(non_neg_integer(), map()) :: {:ok, any()} | {:error, any()}
  defp record_errors(user_job_id, errors) do
    Repo.transaction(fn ->
      user_job =
        UserJob
        |> lock("FOR UPDATE")
        |> Repo.get_by(id: user_job_id)

      existing = user_job.errors || %{}
      merged = Map.put(existing, "errors", Map.merge(Map.get(existing, "errors", %{}), errors))

      UserJob.update_user_job(user_job, %{tasks_done: user_job.tasks_done + 1, errors: merged})
    end)
  end
end
