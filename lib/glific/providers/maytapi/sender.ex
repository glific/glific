defmodule Glific.Providers.Maytapi.Sender do
  @moduledoc """
  Centralizes outbound managed-phone selection for WhatsApp group sends.

  Wraps the primary-with-failover logic: if the group's primary phone is
  healthy on Maytapi we use it; otherwise we promote the next-oldest
  active member and use that. The Maytapi message layer and the response
  handler's retry hook both go through `pick_for_send/2`.
  """

  require Logger
  import Ecto.Query

  alias Glific.{
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Notifications,
    Repo,
    WAGroup.WAManagedPhone
  }

  @typedoc "Why we picked this phone: directly-the-primary, promoted-via-failover, or legacy-column fallback."
  @type source :: :primary | :failover | :legacy_fallback

  @doc """
  Pick the `WAManagedPhone` to send from for `wa_group`.

  ## Options
  - `:exclude` — list of `wa_managed_phone_id`s to skip (used by the
    response-handler retry hook after a send-time error).
  - `:reason` — atom carried into the failover metric/notification.
    Defaults to `:stale_primary_status` (the `WAManagedPhone.status`
    on the primary said it wasn't active). The send-time retry hook passes
    `:send_error` instead.

  ## Returns
  - `{:ok, %WAManagedPhone{}, :primary}` — primary was healthy and
    not excluded.
  - `{:ok, %WAManagedPhone{}, :failover}` — primary unhealthy/excluded;
    promoted the next active member and returned it. Fires a `:warning`
    notification + `glific.maytapi.failover` counter.
  - `{:ok, %WAManagedPhone{}, :legacy_fallback}` — defensive read of
    `wa_group.wa_managed_phone_id` when no `wa_groups_phones` rows exist
    for the group (shouldn't happen post-Phase-1). Logged at warn level.
  - `{:error, :no_active_phones}` — no eligible phone. Fires a
    `:critical` notification + `glific.maytapi.send_no_active_phones`
    counter.
  - `{:error, :promotion_failed}` — the demote-then-promote transaction
    lost a race; caller may retry.
  """
  @spec pick_for_send(WAGroup.t(), keyword()) ::
          {:ok, WAManagedPhone.t(), source()}
          | {:error, :no_active_phones | :promotion_failed}
  def pick_for_send(%WAGroup{} = wa_group, opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [])
    reason = Keyword.get(opts, :reason, :stale_primary_status)

    if memberships_exist?(wa_group.id) do
      pick_from_memberships(wa_group, exclude, reason)
    else
      legacy_fallback(wa_group)
    end
  end

  @doc """
  Promote a managed phone to the group's primary. Thin pass-through to
  `WAGroups.set_primary_phone/2`; exposed here so the Maytapi layer can
  promote without reaching into the Groups context directly.
  """
  @spec promote(non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom() | Ecto.Changeset.t()}
  def promote(wa_group_id, wa_managed_phone_id),
    do: WAGroups.set_primary_phone(wa_group_id, wa_managed_phone_id)

  @spec pick_from_memberships(WAGroup.t(), [non_neg_integer()], atom()) ::
          {:ok, WAManagedPhone.t(), source()}
          | {:error, :no_active_phones | :promotion_failed}
  defp pick_from_memberships(wa_group, exclude, reason) do
    primary = WAGroups.primary_phone(wa_group.id)

    if primary_usable?(primary, exclude) do
      {:ok, primary, :primary}
    else
      failover(wa_group, primary, exclude, reason)
    end
  end

  @spec primary_usable?(WAManagedPhone.t() | nil, [non_neg_integer()]) :: boolean()
  defp primary_usable?(%WAManagedPhone{id: id, status: "active"}, exclude),
    do: id not in exclude

  defp primary_usable?(_, _), do: false

  @spec failover(WAGroup.t(), WAManagedPhone.t() | nil, [non_neg_integer()], atom()) ::
          {:ok, WAManagedPhone.t(), :failover}
          | {:error, :no_active_phones | :promotion_failed}
  defp failover(wa_group, primary, exclude, reason) do
    strict_exclude = if primary, do: Enum.uniq([primary.id | exclude]), else: exclude

    case pick_failover_candidate(wa_group.id, strict_exclude, exclude) do
      {:none} ->
        notify_no_active_phones(wa_group)
        {:error, :no_active_phones}

      {candidate, match} ->
        finish_failover(wa_group, primary, candidate, reason, match)
    end
  end

  # Two-tier candidate selection:
  # 1. `:strict`  — `wa_groups_phones.is_active = true` AND
  #    `wa_managed_phones.status = "active"`, excluding the failed
  #    primary and any caller-passed exclude.
  # 2. `:relaxed` — `wa_groups_phones.is_active = true`, any
  #    `wa_managed_phones.status`. Excludes
  #    ONLY the caller-passed list (NOT the primary) — so a single-member
  #    group with an unhealthy primary can still promote it on a stale-cache
  #    failover. The send-time retry path passes the failed phone in
  #    `exclude` so we don't retry the same phone.
  # No candidate → `{:none}` and the caller fires the critical notification.
  @spec pick_failover_candidate(
          non_neg_integer(),
          [non_neg_integer()],
          [non_neg_integer()]
        ) :: {WAManagedPhone.t(), :strict | :relaxed} | {:none}
  defp pick_failover_candidate(wa_group_id, strict_exclude, relaxed_exclude) do
    case WAGroups.next_active_member(wa_group_id, strict_exclude) do
      %WAManagedPhone{} = phone ->
        {phone, :strict}

      nil ->
        case WAGroups.next_member(wa_group_id, relaxed_exclude) do
          %WAManagedPhone{} = phone -> {phone, :relaxed}
          nil -> {:none}
        end
    end
  end

  @spec finish_failover(
          WAGroup.t(),
          WAManagedPhone.t() | nil,
          WAManagedPhone.t(),
          atom(),
          :strict | :relaxed
        ) :: {:ok, WAManagedPhone.t(), :failover} | {:error, :promotion_failed}
  defp finish_failover(wa_group, primary, candidate, reason, match) do
    case promote(wa_group.id, candidate.id) do
      {:ok, _} ->
        if match == :relaxed do
          Logger.warning(
            "Sender: relaxed promotion — no Maytapi-active member in group #{wa_group.id}; promoting #{candidate.phone} (status=#{candidate.status}) anyway"
          )
        end

        notify_failover(wa_group, primary, candidate, reason, match)
        {:ok, candidate, :failover}

      {:error, err} ->
        Logger.error(
          "Sender: failed to promote wa_managed_phone #{candidate.id} for group #{wa_group.id}: #{inspect(err)}"
        )

        {:error, :promotion_failed}
    end
  end

  @spec legacy_fallback(WAGroup.t()) ::
          {:ok, WAManagedPhone.t(), :legacy_fallback} | {:error, :no_active_phones}
  defp legacy_fallback(%WAGroup{wa_managed_phone_id: nil} = wa_group) do
    Logger.warning(
      "Sender: wa_group #{wa_group.id} has no wa_groups_phones rows and no legacy wa_managed_phone_id"
    )

    notify_no_active_phones(wa_group)
    {:error, :no_active_phones}
  end

  defp legacy_fallback(%WAGroup{wa_managed_phone_id: phone_id} = wa_group) do
    Logger.warning(
      "Sender: wa_group #{wa_group.id} has no wa_groups_phones rows; falling back to legacy wa_managed_phone_id=#{phone_id}"
    )

    case Repo.get(WAManagedPhone, phone_id) do
      nil ->
        notify_no_active_phones(wa_group)
        {:error, :no_active_phones}

      phone ->
        {:ok, phone, :legacy_fallback}
    end
  end

  @spec memberships_exist?(non_neg_integer()) :: boolean()
  defp memberships_exist?(wa_group_id) do
    Repo.exists?(
      from(wa_group_phone in WAGroupPhone,
        where: wa_group_phone.wa_group_id == ^wa_group_id
      )
    )
  end

  @spec notify_failover(
          WAGroup.t(),
          WAManagedPhone.t() | nil,
          WAManagedPhone.t(),
          atom(),
          :strict | :relaxed
        ) :: any()
  defp notify_failover(wa_group, primary, candidate, reason, match) do
    Notifications.create_notification(%{
      category: "WA Group",
      message: failover_message(wa_group, primary, candidate),
      severity: Notifications.types().warning,
      organization_id: wa_group.organization_id,
      entity: %{
        id: wa_group.id,
        label: wa_group.label
      }
    })

    Appsignal.increment_counter("glific.maytapi.failover", 1, %{
      reason: to_string(reason),
      match: to_string(match)
    })
  end

  @spec failover_message(WAGroup.t(), WAManagedPhone.t() | nil, WAManagedPhone.t()) :: String.t()
  defp failover_message(wa_group, %WAManagedPhone{id: id}, %WAManagedPhone{id: id} = candidate) do
    "Primary phone #{candidate.phone} for group #{wa_group.label} shows status '#{candidate.status}' but no backup is available; sending via primary anyway."
  end

  defp failover_message(wa_group, primary, candidate) do
    "Primary phone #{phone_label(primary)} for group #{wa_group.label} is unavailable; switched to phone #{candidate.phone}."
  end

  @spec notify_no_active_phones(WAGroup.t()) :: any()
  defp notify_no_active_phones(wa_group) do
    Notifications.create_notification(%{
      category: "WA Group",
      message: "No active managed phones available for group #{wa_group.label}.",
      severity: Notifications.types().critical,
      organization_id: wa_group.organization_id,
      entity: %{
        id: wa_group.id,
        label: wa_group.label
      }
    })

    Appsignal.increment_counter("glific.maytapi.send_no_active_phones", 1, %{})
  end

  @spec phone_label(WAManagedPhone.t() | nil) :: String.t()
  defp phone_label(nil), do: "(none)"
  defp phone_label(%{phone: phone}), do: phone
end
