defmodule Glific.Groups.WAGroups do
  @moduledoc """
  Whatsapp groups context.
  """
  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroupMemberImport,
    Groups.WAGroupPhone,
    Groups.WAGroupsCollection,
    Providers.Maytapi.ApiClient,
    Repo,
    SafeLog,
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  @no_admin_error "None of your WhatsApp numbers is an admin of this group, so it can't be managed from Glific. Add one of your numbers as a group admin on WhatsApp first."

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
  @spec sync_wa_groups(non_neg_integer()) :: :ok | {:error, String.t()}
  def sync_wa_groups(org_id) do
    # Refresh the phones from Maytapi first (insert new + update existing
    # status), then only pull groups from phones that are active — a
    # disconnected/expired phone can't serve the getGroups call (Maytapi returns
    # "scan a phone into the instance first" and the sync would otherwise fail).
    with :ok <- WAManagedPhones.fetch_wa_managed_phones(org_id) do
      %{organization_id: org_id}
      |> WAManagedPhones.list_wa_managed_phones()
      |> Enum.filter(fn wa_managed_phone -> wa_managed_phone.status == "active" end)
      |> Enum.each(fn wa_managed_phone ->
        do_sync_wa_groups(org_id, wa_managed_phone)
      end)
    end
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
        {:error, SafeLog.safe_inspect(message)}
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
            "Skipping participant #{phone}: could not resolve contact: #{SafeLog.safe_inspect(changeset.errors)}"
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
    all_managed_phones = WAManagedPhones.list_wa_managed_phones(%{organization_id: org_id})

    present_group_ids =
      Enum.flat_map(group_details, fn group ->
        case fetch_oldest_wa_group(group.bsp_id) do
          nil ->
            Logger.warning(
              "Could not upsert wa_groups_phones row for WA group #{group.bsp_id} (phone #{wa_managed_phone.phone_id}): group not found in DB"
            )

            []

          wa_group ->
            reconcile_managed_phones(wa_group, group.participants, all_managed_phones, org_id)
            [wa_group.id]
        end
      end)

    deactivate_missing_memberships(wa_managed_phone, present_group_ids)
    :ok
  end

  # For every managed phone in the org (including the one that called
  # Maytapi): if the phone's number is in this group's `participants`
  # list, upsert its membership as `is_active: true`; otherwise mark its
  # existing membership `is_active: false`.
  @spec reconcile_managed_phones(
          WAGroup.t(),
          [String.t()],
          [WAManagedPhone.t()],
          non_neg_integer()
        ) :: :ok
  defp reconcile_managed_phones(wa_group, participants, managed_phones, org_id) do
    participant_phones =
      participants
      |> Enum.map(&phone_number/1)
      |> MapSet.new()

    Enum.each(managed_phones, fn managed_phone ->
      if MapSet.member?(participant_phones, managed_phone.phone) do
        case ensure_membership(wa_group.id, managed_phone.id, org_id, is_primary: false) do
          {:ok, _membership} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Could not upsert wa_groups_phones row for WA group #{wa_group.bsp_id} (phone #{managed_phone.phone_id}): #{SafeLog.safe_inspect(reason)}"
            )
        end
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
      [wa_group_phone],
      wa_group_phone.wa_group_id == ^wa_group_id and
        wa_group_phone.wa_managed_phone_id == ^wa_managed_phone_id and
        wa_group_phone.is_active == true
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
  Return the oldest active membership's managed phone for a group.

  `exclude` is a list of `wa_managed_phone_id`s to skip while selecting the
  candidate — the failover path passes the phone(s) it has already tried
  (e.g. the unhealthy primary, or a phone that just errored on send) so the
  same phone isn't picked again. Pass `[]` to consider every member.

  "Active" here means BOTH `wa_groups_phones.is_active == true` AND
  `wa_managed_phones.status == "active"`.

  Used by `Glific.Providers.Maytapi.Sender.pick_for_send/2` as the *strict*
  failover candidate when the current primary is unhealthy. Returns `nil`
  when no eligible member exists.
  """
  @spec next_active_member(non_neg_integer(), [non_neg_integer()]) ::
          WAManagedPhone.t() | nil
  def next_active_member(wa_group_id, exclude \\ []) do
    next_member_query(wa_group_id, exclude)
    |> where([_wa_group_phone, wa_managed_phone], wa_managed_phone.status == "active")
    |> Repo.one()
  end

  @doc """
  Return the oldest active membership's managed phone for a group, ignoring
  the Maytapi `WAManagedPhone.status`. Caller is opting in to "best-effort"
  selection — used by `Glific.Providers.Maytapi.Sender` as a relaxed
  fallback when no Maytapi-active phone exists for the group; the cached
  status might be stale and trying a phone is better than refusing the
  send outright. Returns `nil` when the group has no membership rows with
  `wa_groups_phones.is_active == true` (either no memberships at all, or
  every membership is inactive).
  """
  @spec next_member(non_neg_integer(), [non_neg_integer()]) ::
          WAManagedPhone.t() | nil
  def next_member(wa_group_id, exclude \\ []) do
    next_member_query(wa_group_id, exclude)
    |> Repo.one()
  end

  @spec next_member_query(non_neg_integer(), [non_neg_integer()]) :: Ecto.Query.t()
  defp next_member_query(wa_group_id, exclude) do
    WAGroupPhone
    |> join(:inner, [wa_group_phone], wa_managed_phone in WAManagedPhone,
      on: wa_managed_phone.id == wa_group_phone.wa_managed_phone_id
    )
    |> where(
      [wa_group_phone, _wa_managed_phone],
      wa_group_phone.wa_group_id == ^wa_group_id and
        wa_group_phone.is_active == true and
        wa_group_phone.wa_managed_phone_id not in ^exclude
    )
    |> order_by([wa_group_phone, _wa_managed_phone],
      asc: wa_group_phone.inserted_at,
      asc: wa_group_phone.id
    )
    |> limit(1)
    |> select([_wa_group_phone, wa_managed_phone], wa_managed_phone)
  end

  @doc """
  The managed phone that performs Maytapi group-management actions (rename,
  add/remove members) for `wa_group_id`: one of our managed numbers whose
  contact is an admin of this group. The caller (frontend) never chooses it —
  Maytapi only honours actions from a group admin, so we resolve it server-side.

  Admin membership is kept fresh by the group sync, so when none of our numbers
  is an admin we genuinely cannot act on the group — this returns `nil` and the
  caller surfaces an error. There is deliberately **no** primary-phone fallback:
  a non-admin phone would just be rejected by Maytapi.
  """
  @spec acting_phone(non_neg_integer()) :: WAManagedPhone.t() | nil
  def acting_phone(wa_group_id) do
    admin_ids = admin_contact_ids(wa_group_id)

    WAManagedPhone
    |> where([wmp], wmp.contact_id in ^admin_ids)
    |> order_by([wmp], asc: wmp.id)
    |> limit(1)
    |> Repo.one()
  end

  # Glific contact ids that are admins of this group.
  @spec admin_contact_ids(non_neg_integer()) :: [non_neg_integer()]
  defp admin_contact_ids(wa_group_id) do
    ContactWAGroup
    |> where([cwg], cwg.wa_group_id == ^wa_group_id and cwg.is_admin == true)
    |> select([cwg], cwg.contact_id)
    |> Repo.all()
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
      [wa_group_phone],
      wa_group_phone.wa_managed_phone_id == ^wa_managed_phone.id and
        wa_group_phone.wa_group_id not in ^present_group_ids and
        wa_group_phone.is_active == true
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
          "Failed to set maytapi webhook for #{org_details.shortcode} due to #{SafeLog.safe_inspect(body)}"
        )

        {:error, "Failed to set maytapi webhook. Try Again"}

      {:error, error} ->
        Logger.error(
          "Failed to set maytapi webhook for #{org_details.shortcode} due to #{SafeLog.safe_inspect(error)}"
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
  Provision a WhatsApp group for the `createWaGroup` mutation. Members are
  supplied via a CSV `import_data`.

  Maytapi's createGroup is seeded with just the first phone (it rejects an empty
  list and gets slow with many), then a background job adds the rest and creates
  the contacts (phone + optional name). `input` is the GraphQL input map
  (`:wa_managed_phone_id`, `:name`, `:import_data`).
  """
  @spec provision_wa_group(non_neg_integer(), map()) ::
          {:ok, WAGroup.t()} | {:error, any()}
  def provision_wa_group(org_id, %{
        wa_managed_phone_id: wa_managed_phone_id,
        name: name,
        import_data: import_data
      }) do
    # Seed createGroup with the CSV's first phone (Maytapi rejects an empty list),
    # then a background job adds the rest and creates the contacts.
    numbers = import_data |> WAGroupMemberImport.extract_phones() |> Enum.take(1)

    with {:ok, wa_group} <-
           create_group_via_maytapi(org_id, wa_managed_phone_id, %{name: name, numbers: numbers}) do
      WAGroupMemberImport.import_members(org_id, wa_group.id, data: import_data)
      {:ok, wa_group}
    end
  end

  @doc """
  Provision a new WhatsApp group via Maytapi from `wa_managed_phone_id`.

  Calls `ApiClient.create_group/3`; on success persists the new `wa_groups`
  row plus an `is_primary: true` membership for the creating phone.

  `attrs` shape:
      %{name: "Group name", numbers: ["91xxxxxxxxxx", ...]}
  """
  @spec create_group_via_maytapi(non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, WAGroup.t()} | {:error, any()}
  def create_group_via_maytapi(org_id, wa_managed_phone_id, attrs) do
    numbers = attrs[:numbers] || []

    with {:ok, wa_managed_phone} <-
           Repo.fetch_by(WAManagedPhone, %{id: wa_managed_phone_id, organization_id: org_id}),
         {:ok, group_data} <-
           ApiClient.create_group(org_id, wa_managed_phone.phone_id, %{
             name: attrs[:name],
             numbers: numbers
           }),
         {:ok, wa_group} <-
           maybe_create_group(%{
             label: attrs[:name],
             bsp_id: group_data.bsp_id,
             organization_id: org_id,
             wa_managed_phone_id: wa_managed_phone_id
           }) do
      sync_contacts(
        %{participants: group_data.participants, admins: group_data.admins},
        wa_group.id,
        org_id
      )

      {:ok, wa_group}
    else
      {:error, reason} ->
        Glific.log_error(
          "Maytapi create_group failed: org=#{org_id} reason=#{SafeLog.safe_inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Fetch a WhatsApp group by id (scoped to `org_id`) and remove `contact_id` from
  it via Maytapi (`group/remove`). Entry point for the `removeWaGroupContact`
  mutation. The acting phone is resolved via `acting_phone/1` (a managed number
  whose contact is a group admin), since Maytapi only honours actions from a group
  admin.

  Returns `{:ok, wa_group}`, or `{:error, reason}` when the group is not found,
  none of the org's numbers is an admin of the group, or Maytapi rejects the
  removal. The removal itself is delegated to `ContactWAGroups.remove_member/3`.
  """
  @spec remove_wa_group_contact(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, WAGroup.t()} | {:error, any()}
  def remove_wa_group_contact(org_id, wa_group_id, contact_id) do
    with {:ok, %WAGroup{} = wa_group} <-
           Repo.fetch_by(WAGroup, %{id: wa_group_id, organization_id: org_id}),
         %WAManagedPhone{id: wa_managed_phone_id} <- acting_phone(wa_group.id),
         {:ok, _removed} <-
           ContactWAGroups.remove_member(wa_group, wa_managed_phone_id, contact_id) do
      {:ok, wa_group}
    else
      nil -> {:error, @no_admin_error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch a WhatsApp group by id (scoped to `org_id`) and add `phones` to it via
  Maytapi. Entry point for the background CSV member import
  (`WAGroupMemberImportWorker`) — adding members is never a foreground/GraphQL
  action. The acting phone is resolved via `acting_phone/1`, then each phone is
  added with its own Maytapi call (so one bad number doesn't fail the rest) and
  its contact is created on the fly if missing.

  Returns `{:ok, %{added: n, failed: %{phone => message}}}` where `failed` holds
  the numbers Maytapi rejected, or `{:error, reason}` when the group is not found
  or none of the org's numbers is an admin of the group.
  """
  @spec add_members_to_group(non_neg_integer(), non_neg_integer(), [String.t()]) ::
          {:ok, %{added: non_neg_integer(), failed: %{String.t() => String.t()}}}
          | {:error, any()}
  def add_members_to_group(org_id, wa_group_id, phones) do
    with {:ok, %WAGroup{} = wa_group} <-
           Repo.fetch_by(WAGroup, %{id: wa_group_id, organization_id: org_id}),
         %WAManagedPhone{id: wa_managed_phone_id} <- acting_phone(wa_group.id) do
      ContactWAGroups.add_members(wa_group, wa_managed_phone_id, phones)
    else
      nil -> {:error, @no_admin_error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch a WhatsApp group by id (scoped to `org_id`) and bulk-import members from
  a CSV. Entry point for the `importWaGroupContacts` mutation.
  """
  @spec import_wa_group_contacts(non_neg_integer(), non_neg_integer(), atom(), String.t()) ::
          {:ok, map()} | {:error, any()}
  def import_wa_group_contacts(org_id, wa_group_id, type, data) do
    with {:ok, wa_group} <-
           Repo.fetch_by(WAGroup, %{id: wa_group_id, organization_id: org_id}) do
      WAGroupMemberImport.import_members(org_id, wa_group.id, [{type, data}])
    end
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
