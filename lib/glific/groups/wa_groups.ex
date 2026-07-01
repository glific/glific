defmodule Glific.Groups.WAGroups do
  @moduledoc """
  Whatsapp groups context.
  """
  import Ecto.Query, warn: false

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroupsCollection,
    Providers.Maytapi.ApiClient,
    Repo,
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:include_groups, []}, query ->
        query

      {:include_groups, group_ids}, query ->
        sub_query =
          WAGroupsCollection
          |> where([wc], wc.group_id in ^group_ids)
          |> select([wa], wa.wa_group_id)

        query
        |> where([wg], wg.id in subquery(sub_query))

      {:exclude_groups, []}, query ->
        query

      {:exclude_groups, group_ids}, query ->
        sub_query =
          WAGroupsCollection
          |> where([wc], wc.group_id in ^group_ids)
          |> select([wc], wc.wa_group_id)

        query
        |> where([c], c.id not in subquery(sub_query))

      {:term, term}, query ->
        query |> where([wa_grp], ilike(wa_grp.label, ^"%#{term}%"))

      _, query ->
        query
    end)
  end

  @doc """
  get all the wa groups associated with the group
  """
  @spec wa_groups(map()) :: [WAGroup.t()]
  def wa_groups(args) do
    args
    |> Repo.list_filter_query(WAGroup, &Repo.opts_with_label/2, &filter_with/2)
    |> Repo.all()
  end

  @spec phone_number(String.t()) :: non_neg_integer()
  defp phone_number(phone_number), do: String.split(phone_number, "@") |> List.first()

  @doc """
  Syncs groups and phones using maytapi API into Glific
  """
  @spec sync_wa_groups(non_neg_integer()) :: :ok
  def sync_wa_groups(org_id) do
    wa_managed_phones =
      WAManagedPhones.list_wa_managed_phones(%{organization_id: org_id})

    Enum.each(wa_managed_phones, fn wa_managed_phone ->
      do_sync_wa_groups(org_id, wa_managed_phone)
    end)
  end

  @spec do_sync_wa_groups(non_neg_integer(), map()) :: list() | {:error, any()}
  defp do_sync_wa_groups(org_id, wa_managed_phone) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_groups(org_id, wa_managed_phone.phone_id),
         {:ok, decoded} <- Jason.decode(body) do
      group_details = get_group_details(decoded, wa_managed_phone)
      create_whatsapp_groups(group_details, org_id)
      sync_wa_groups_with_contacts(group_details, org_id)
      sync_wa_group_phones(group_details, wa_managed_phone)
    else
      {:ok, %Tesla.Env{body: body}} ->
        {:error, body}

      {:error, message} ->
        {:error, Glific.SafeLog.safe_inspect(message)}
    end
  end

  @spec get_group_details(map(), WAManagedPhone.t()) :: [map()]
  defp get_group_details(%{"data" => groups}, wa_managed_phone) when is_list(groups) do
    Enum.reduce(groups, [], fn group, acc ->
      if group["name"] != nil and group["name"] != "" do
        [
          %{
            name: group["name"],
            bsp_id: group["id"],
            wa_managed_phone_id: wa_managed_phone.id,
            participants: group["participants"] || [],
            admins: group["admins"]
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  @doc """
  Syncs the contacts in each WA group by diffing Maytapi's participant list
  against the current `contacts_wa_groups` rows: new participants are
  inserted, departed participants are deleted, retained participants whose
  admin status changed are updated, and rows whose contact + admin flag
  already match Maytapi are left untouched (no `updated_at` bump, so no
  downstream resync churn).
  """
  @spec sync_wa_groups_with_contacts(list(), non_neg_integer()) :: :ok
  def sync_wa_groups_with_contacts(group_details, org_id) do
    Enum.each(group_details, fn group ->
      case fetch_oldest_wa_group(group.bsp_id) do
        nil ->
          Logger.warning(
            "Skipping contact sync for WA group #{group.bsp_id} (phone #{group.wa_managed_phone_id}): group not found in DB"
          )

        wa_group ->
          sync_contacts(group, wa_group.id, org_id)
      end
    end)
  end

  @spec sync_contacts(map(), non_neg_integer(), non_neg_integer()) :: :ok
  defp sync_contacts(group, wa_group_id, org_id) do
    admin_phones = Enum.map(group.admins || [], &phone_number/1)
    maytapi_participants = maybe_create_contacts(group.participants, admin_phones, org_id)
    existing_contact_wa_groups = existing_contact_wa_groups(wa_group_id)

    insert_new_contact_wa_groups(
      maytapi_participants,
      existing_contact_wa_groups,
      wa_group_id,
      org_id
    )

    update_contact_wa_group_admin_flags(maytapi_participants, existing_contact_wa_groups)

    delete_departed_contact_wa_groups(
      maytapi_participants,
      existing_contact_wa_groups,
      wa_group_id
    )

    :ok
  end

  # Who Maytapi says is in the group right now: %{contact_id => is_admin}.
  # Contacts are created on the fly so we always have an id to compare.
  @spec maybe_create_contacts([String.t()], [String.t()], non_neg_integer()) ::
          %{non_neg_integer() => boolean()}
  defp maybe_create_contacts(participants, admin_phones, org_id) do
    Enum.reduce(participants, %{}, fn participant, acc ->
      phone = phone_number(participant)

      case Contacts.maybe_create_contact(%{
             phone: phone,
             organization_id: org_id,
             contact_type: "WA"
           }) do
        {:ok, contact} ->
          Map.put(acc, contact.id, phone in admin_phones)

        {:error, changeset} ->
          Logger.warning(
            "Skipping participant #{phone}: could not resolve contact: #{Glific.SafeLog.safe_inspect(changeset.errors)}"
          )

          acc
      end
    end)
  end

  # Keep full rows so we can compare each retained member's is_admin
  # flag against what Maytapi now reports.
  @spec existing_contact_wa_groups(non_neg_integer()) :: %{
          non_neg_integer() => ContactWAGroup.t()
        }
  defp existing_contact_wa_groups(wa_group_id) do
    ContactWAGroup
    |> where([c], c.wa_group_id == ^wa_group_id)
    |> Repo.all()
    |> Map.new(&{&1.contact_id, &1})
  end

  @spec insert_new_contact_wa_groups(
          %{non_neg_integer() => boolean()},
          %{non_neg_integer() => ContactWAGroup.t()},
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  defp insert_new_contact_wa_groups(
         maytapi_participants,
         existing_contact_wa_groups,
         wa_group_id,
         org_id
       ) do
    existing_contact_wa_groups_ids = MapSet.new(Map.keys(existing_contact_wa_groups))
    maytapi_participants_ids = MapSet.new(Map.keys(maytapi_participants))

    for contact_id <- MapSet.difference(maytapi_participants_ids, existing_contact_wa_groups_ids) do
      ContactWAGroups.create_contact_wa_group(%{
        contact_id: contact_id,
        wa_group_id: wa_group_id,
        organization_id: org_id,
        is_admin: Map.fetch!(maytapi_participants, contact_id)
      })
    end

    :ok
  end

  # Reconcile is_admin only when it actually changed, so unchanged rows keep
  # their original updated_at.
  @spec update_contact_wa_group_admin_flags(
          %{non_neg_integer() => boolean()},
          %{non_neg_integer() => ContactWAGroup.t()}
        ) :: :ok
  defp update_contact_wa_group_admin_flags(maytapi_participants, existing_contact_wa_groups) do
    existing_contact_wa_groups_ids = MapSet.new(Map.keys(existing_contact_wa_groups))
    maytapi_participants_ids = MapSet.new(Map.keys(maytapi_participants))

    for contact_id <-
          MapSet.intersection(maytapi_participants_ids, existing_contact_wa_groups_ids) do
      contact_wa_group = existing_contact_wa_groups[contact_id]
      desired_admin = Map.fetch!(maytapi_participants, contact_id)

      if contact_wa_group.is_admin != desired_admin do
        contact_wa_group
        |> Ecto.Changeset.change(is_admin: desired_admin)
        |> Repo.update()
      end
    end

    :ok
  end

  @spec delete_departed_contact_wa_groups(
          %{non_neg_integer() => boolean()},
          %{non_neg_integer() => ContactWAGroup.t()},
          non_neg_integer()
        ) :: :ok
  defp delete_departed_contact_wa_groups(
         maytapi_participants,
         existing_contact_wa_groups,
         wa_group_id
       ) do
    existing_contact_wa_groups_ids = MapSet.new(Map.keys(existing_contact_wa_groups))
    maytapi_participants_ids = MapSet.new(Map.keys(maytapi_participants))

    to_remove =
      MapSet.difference(existing_contact_wa_groups_ids, maytapi_participants_ids)
      |> MapSet.to_list()

    if to_remove != [] do
      ContactWAGroup
      |> where([c], c.wa_group_id == ^wa_group_id and c.contact_id in ^to_remove)
      |> Repo.delete_all()
    end

    :ok
  end

  @doc """
  Upserts `wa_groups_phones` memberships from a single phone's Maytapi
  `getGroups` response. Groups the phone is currently in are marked
  `is_active: true`; memberships for groups no longer returned are marked
  `is_active: false`. `is_primary` is never touched here.
  """
  @spec sync_wa_group_phones(list(), WAManagedPhone.t()) :: :ok
  def sync_wa_group_phones(group_details, wa_managed_phone) do
    org_id = wa_managed_phone.organization_id

    # Cross-phone reconciliation needs every other managed phone in the
    # org so it can check each one against this group's participants list.
    other_managed_phones =
      WAManagedPhones.list_wa_managed_phones(%{organization_id: org_id})
      |> Enum.reject(&(&1.id == wa_managed_phone.id))

    present_group_ids =
      Enum.flat_map(group_details, fn group ->
        case fetch_oldest_wa_group(group.bsp_id) do
          nil ->
            Logger.warning(
              "Could not upsert wa_groups_phones row for WA group #{group.bsp_id} (phone #{wa_managed_phone.phone_id}): group not found in DB"
            )

            []

          wa_group ->
            case ensure_membership(wa_group.id, wa_managed_phone.id, org_id, is_primary: false) do
              {:ok, _membership} ->
                :ok

              {:error, reason} ->
                Logger.warning(
                  "Could not upsert wa_groups_phones row for WA group #{group.bsp_id} (phone #{wa_managed_phone.phone_id}): #{Glific.SafeLog.safe_inspect(reason)}"
                )
            end

            reconcile_other_managed_phones(
              wa_group,
              group.participants,
              other_managed_phones,
              org_id
            )

            [wa_group.id]
        end
      end)

    deactivate_missing_memberships(wa_managed_phone, present_group_ids)
    :ok
  end

  # Use the participants list from one phone's view of the group to fix
  # the membership rows of all OTHER managed phones in the same group:
  # in participants → active, not in participants → inactive.
  #
  # Without this, a phone whose own sync is stale or skipped keeps a
  # wrong `is_active` flag until its next successful sync.
  @spec reconcile_other_managed_phones(
          WAGroup.t(),
          [String.t()],
          [WAManagedPhone.t()],
          non_neg_integer()
        ) :: :ok
  defp reconcile_other_managed_phones(wa_group, participants, other_managed_phones, org_id) do
    participant_phones =
      participants
      |> Enum.map(&phone_number/1)
      |> MapSet.new()

    Enum.each(other_managed_phones, fn managed_phone ->
      if MapSet.member?(participant_phones, managed_phone.phone) do
        ensure_membership(wa_group.id, managed_phone.id, org_id, is_primary: false)
      else
        deactivate_one_membership(wa_group.id, managed_phone.id)
      end
    end)

    :ok
  end

  @spec deactivate_one_membership(non_neg_integer(), non_neg_integer()) :: :ok
  defp deactivate_one_membership(wa_group_id, wa_managed_phone_id) do
    WAGroupPhone
    |> where(
      [wgp],
      wgp.wa_group_id == ^wa_group_id and
        wgp.wa_managed_phone_id == ^wa_managed_phone_id and
        wgp.is_active == true
    )
    |> Repo.update_all(set: [is_active: false, updated_at: DateTime.utc_now()])

    :ok
  end

  # Idempotent upsert. On a new row, `is_primary` is stamped per the caller's
  # context (sync passes `is_primary: false` since it doesn't manage primary
  # — only Phase 4's failover path does). On conflict, only `is_active` and
  # `updated_at` are touched, so existing primary status stays intact.
  @spec ensure_membership(non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, WAGroupPhone.t()} | {:error, Ecto.Changeset.t()}
  defp ensure_membership(wa_group_id, wa_managed_phone_id, organization_id, opts) do
    is_primary = Keyword.get(opts, :is_primary, false)

    %WAGroupPhone{}
    |> WAGroupPhone.changeset(%{
      wa_group_id: wa_group_id,
      wa_managed_phone_id: wa_managed_phone_id,
      organization_id: organization_id,
      is_primary: is_primary,
      is_active: true
    })
    |> Repo.insert(
      on_conflict: [set: [is_active: true, updated_at: DateTime.utc_now()]],
      conflict_target: [:wa_group_id, :wa_managed_phone_id]
    )
  end

  @doc """
  Return the `WAManagedPhone` whose membership row in `wa_groups_phones`
  is `is_primary: true` and `is_active: true` for the given group.
  Returns `nil` if no primary is set (legacy data or all memberships
  have been deactivated).
  """
  @spec primary_phone(non_neg_integer()) :: WAManagedPhone.t() | nil
  def primary_phone(wa_group_id) do
    case Repo.get_by(WAGroupPhone, %{
           wa_group_id: wa_group_id,
           is_primary: true,
           is_active: true
         }) do
      nil -> nil
      wa_group_phone -> Repo.preload(wa_group_phone, :wa_managed_phone).wa_managed_phone
    end
  end

  @doc """
  Promote a different managed phone to be the group's primary. Demote the
  current primary and promote the target in a single transaction.

  Returns:
  - `{:ok, %{primary_phone: row, warning: string | nil}}` — `warning` is non-nil when the target phone's Maytapi `status != "active"`, so the UI can surface a confirmation ("phone is reconnecting, messages may fail") without the backend blocking the change. The operator may be intentionally pre-staging a switch during an outage.
  - `{:error, :membership_not_found}` — no `(wa_group_id, wa_managed_phone_id)` row exists
  - `{:error, :inactive_membership}` — target row exists but `is_active == false`
  - `{:error, %Ecto.Changeset{}}` — surfaces the `wa_groups_phones_one_primary` partial-unique-index violation if it ever fires (it shouldn't, since we demote first)
  """
  @spec set_primary_phone(non_neg_integer(), non_neg_integer()) ::
          {:ok, %{primary_phone: WAGroupPhone.t(), warning: String.t() | nil}}
          | {:error, atom() | Ecto.Changeset.t()}
  def set_primary_phone(wa_group_id, wa_managed_phone_id) do
    Repo.transaction(fn ->
      with {:ok, target} <- fetch_target_membership(wa_group_id, wa_managed_phone_id),
           :ok <- validate_active(target),
           {:ok, promoted} <- maybe_swap_primary(target, wa_group_id) do
        %{primary_phone: promoted, warning: phone_status_warning(wa_managed_phone_id)}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # If the target is already primary, no DB writes are needed. Otherwise
  # demote the current primary and promote the target in that order — the
  # partial unique index `wa_groups_phones_one_primary` forbids two
  # `is_primary: true` rows per group, so demote must come first.
  @spec maybe_swap_primary(WAGroupPhone.t(), non_neg_integer()) ::
          {:ok, WAGroupPhone.t()} | {:error, Ecto.Changeset.t()}
  defp maybe_swap_primary(%{is_primary: true} = target, _wa_group_id), do: {:ok, target}

  defp maybe_swap_primary(target, wa_group_id) do
    with {:ok, _} <- demote_current_primary(wa_group_id) do
      promote_to_primary(target)
    end
  end

  @spec fetch_target_membership(non_neg_integer(), non_neg_integer()) ::
          {:ok, WAGroupPhone.t()} | {:error, :membership_not_found}
  defp fetch_target_membership(wa_group_id, wa_managed_phone_id) do
    case Repo.get_by(WAGroupPhone, %{
           wa_group_id: wa_group_id,
           wa_managed_phone_id: wa_managed_phone_id
         }) do
      nil -> {:error, :membership_not_found}
      membership -> {:ok, membership}
    end
  end

  @spec validate_active(WAGroupPhone.t()) :: :ok | {:error, :inactive_membership}
  defp validate_active(%{is_active: true}), do: :ok
  defp validate_active(_), do: {:error, :inactive_membership}

  @spec phone_status_warning(non_neg_integer()) :: String.t() | nil
  defp phone_status_warning(wa_managed_phone_id) do
    case Repo.get(WAManagedPhone, wa_managed_phone_id) do
      %{status: status, phone: phone} when status != "active" ->
        message =
          "WhatsApp phone #{phone} is currently '#{status}' on Maytapi. Messages may fail until it reconnects."

        Logger.warning("set_primary_phone with non-active phone: #{message}")
        message

      _ ->
        nil
    end
  end

  @spec demote_current_primary(non_neg_integer()) ::
          {:ok, WAGroupPhone.t() | nil} | {:error, Ecto.Changeset.t()}
  defp demote_current_primary(wa_group_id) do
    case Repo.get_by(WAGroupPhone, %{wa_group_id: wa_group_id, is_primary: true}) do
      nil ->
        {:ok, nil}

      current_primary ->
        current_primary
        |> WAGroupPhone.changeset(%{is_primary: false})
        |> Repo.update()
    end
  end

  @spec promote_to_primary(WAGroupPhone.t()) ::
          {:ok, WAGroupPhone.t()} | {:error, Ecto.Changeset.t()}
  defp promote_to_primary(membership) do
    membership
    |> WAGroupPhone.changeset(%{is_primary: true})
    |> Repo.update()
  end

  @spec deactivate_missing_memberships(WAManagedPhone.t(), [non_neg_integer()]) :: :ok
  defp deactivate_missing_memberships(wa_managed_phone, present_group_ids) do
    WAGroupPhone
    |> where(
      [wgp],
      wgp.wa_managed_phone_id == ^wa_managed_phone.id and
        wgp.wa_group_id not in ^present_group_ids and
        wgp.is_active == true
    )
    |> Repo.update_all(set: [is_active: false, updated_at: DateTime.utc_now()])

    :ok
  end

  @spec create_whatsapp_groups(list(), non_neg_integer) :: list()
  defp create_whatsapp_groups(groups, org_id) do
    Enum.map(
      groups,
      fn group ->
        maybe_create_group(%{
          label: group.name,
          organization_id: org_id,
          bsp_id: group.bsp_id,
          wa_managed_phone_id: group.wa_managed_phone_id,
          last_communication_at: DateTime.utc_now()
        })
      end
    )
  end

  @doc """
  Creates a wa_group.

  ## Examples

      iex> create_wa_group(%{field: value})
      {:ok, %WAGroup{}}

      iex> create_wa_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_wa_group(map()) :: {:ok, WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_group(attrs \\ %{}) do
    %WAGroup{}
    |> WAGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of wa_groups.

  ## Examples

      iex> list_wa_groups()
      [%WAManagedPhone{}, ...]

  """
  @spec list_wa_groups(map()) :: [WAGroup.t()]
  def list_wa_groups(args) do
    args
    |> Repo.list_filter_query(WAGroup, &Repo.opts_with_name/2, &Repo.filter_with/2)
    |> Repo.all()
  end

  @doc """
  Gets a single wa_group.

  Raises `Ecto.NoResultsError` if the wa group does not exist.

  ## Examples

      iex> get_wa_group!(123)
      %WAGroup{}

      iex> get_wa_group!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_wa_group!(non_neg_integer()) :: WAGroup.t()
  def get_wa_group!(id), do: Repo.get!(WAGroup, id)

  @doc """
  Gets a wa_groups from list of IDs.

  ## Examples

      iex> get_wa_groups!([123])
      [%WAGroup{}]

      iex> get_wa_groups!([456])
      []

  """
  @spec get_wa_groups!([non_neg_integer()]) :: list(WAGroup.t())
  def get_wa_groups!(ids) do
    WAGroup
    |> where([wag], wag.id in ^ids)
    |> Repo.all()
  end

  @doc """
  Fetches a WA group by `(bsp_id, organization_id)`. If none exists, creates
  one; if duplicates exist (legacy data from before Phase 3 — Phase 5 will
  collapse these), returns the oldest. In all cases ensures a
  `wa_groups_phones` membership row exists for the calling
  `wa_managed_phone_id` so that subsequent outbound routing knows the phone
  is in the group:

  - Newly created group → calling phone is recorded as `is_primary: true`
    (first creator becomes the primary, matching the Phase 1 backfill
    convention).
  - Existing group → calling phone is recorded as `is_primary: false`
    (joining an existing group doesn't change who's primary).

  Existing membership rows are left as-is for `is_primary`; only
  `is_active` gets re-stamped to `true`.
  """
  @spec maybe_create_group(map()) ::
          {:ok, Glific.Groups.WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def maybe_create_group(params) do
    case fetch_oldest_wa_group(params.bsp_id) do
      nil ->
        with {:ok, wa_group} <- create_wa_group(params) do
          ensure_membership(wa_group.id, params.wa_managed_phone_id, params.organization_id,
            is_primary: true
          )

          {:ok, wa_group}
        end

      wa_group ->
        ensure_membership(wa_group.id, params.wa_managed_phone_id, params.organization_id,
          is_primary: false
        )

        if params.label && wa_group.label != params.label do
          update_wa_group(wa_group, %{label: params.label})
        else
          {:ok, wa_group}
        end
    end
  end

  @doc """
  Look up a `wa_group` by its WhatsApp `bsp_id`. If duplicate rows exist
  from before Phase 3, the oldest one wins — matches the Phase 1 backfill's
  "oldest = primary" convention so the active group stays stable.
  """
  @spec fetch_oldest_wa_group(String.t()) :: WAGroup.t() | nil
  def fetch_oldest_wa_group(bsp_id) do
    WAGroup
    |> where([wg], wg.bsp_id == ^bsp_id)
    |> order_by([wg], asc: wg.inserted_at, asc: wg.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  get all the wa groups associated with the group
  """
  @spec wa_groups_count(map()) :: integer()
  def wa_groups_count(args) do
    args
    |> Repo.list_filter_query(WAGroup, nil, &filter_with/2)
    |> Repo.aggregate(:count)
  end

  @doc """
  Sets the maytapi webhook for the org
  """
  @spec set_webhook_endpoint(map()) :: :ok | {:error, String.t()}
  def set_webhook_endpoint(org_details) do
    payload = %{
      "webhook" => Glific.api_callback_base(org_details.shortcode) <> "/maytapi"
    }

    case ApiClient.set_webhook(org_details.id, payload) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Tesla.Env{body: body}} ->
        Logger.error(
          "Failed to set maytapi webhook for #{org_details.shortcode} due to #{Glific.SafeLog.safe_inspect(body)}"
        )

        {:error, "Failed to set maytapi webhook. Try Again"}

      {:error, error} ->
        Logger.error(
          "Failed to set maytapi webhook for #{org_details.shortcode} due to #{Glific.SafeLog.safe_inspect(error)}"
        )

        {:error, "Failed to set maytapi webhook. Try Again"}
    end
  end

  @doc """
  Updates a wa_group.

  ## Examples

    iex> update_wa_group(%{fields: value})
    {:ok, %WAGroup{}}

    iex> update_wa_group(%{fields: bad_value})
    {:error, %Ecto.Changeset{}}
  """
  @spec update_wa_group(WAGroup.t(), map()) :: {:ok, WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def update_wa_group(wa_group, attrs \\ %{}) do
    wa_group
    |> WAGroup.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a WAGroup.t() as map
  """
  @spec get_wa_group_map(integer()) :: map()
  def get_wa_group_map(wa_group_id) do
    get_wa_group!(wa_group_id)
    |> Map.from_struct()
  end
end
