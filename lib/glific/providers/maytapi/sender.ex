defmodule Glific.Providers.Maytapi.Sender do
  @moduledoc """
  Centralizes outbound managed-phone selection for WhatsApp group sends.

  Wraps the primary-with-failover logic: if the group's primary phone is
  healthy on Maytapi we use it; otherwise we promote the next-oldest
  active member and use that. The Maytapi message layer and the response
  handler's retry hook both go through `pick_for_send/2`.
  """

  require Logger

  alias Glific.{
    Groups.WAGroup,
    Groups.WAGroups,
    Notifications,
    WAGroup.WAManagedPhone
  }

  @typedoc "Why we picked this phone: directly-the-primary or promoted-via-failover."
  @type source :: :primary | :failover

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

    pick_from_memberships(wa_group, exclude, reason)
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
    case pick_failover_candidate(wa_group.id, primary, exclude) do
      nil ->
        notify_no_active_phones(wa_group)
        {:error, :no_active_phones}

      candidate ->
        finish_failover(wa_group, primary, candidate, reason)
    end
  end

  # Three passes, each keeping the failed primary excluded until the last
  # so a stale-cache primary isn't re-picked when ANY backup exists:
  #   1. Active backup — `wa_managed_phones.status = "active"`.
  #   2. Any-status backup — primary still excluded, so the next-oldest
  #      backup wins even if its cached status says it isn't active.
  #   3. Primary itself — only reached when the group has no backup; this
  #      is the single-member-group / "promote-anyway" path. The retry hook
  #      passes the failed phone in `exclude`, so it can't be re-picked here.
  # Downstream uses `candidate.status` to tell whether the pick was a fallback.
  @spec pick_failover_candidate(
          non_neg_integer(),
          WAManagedPhone.t() | nil,
          [non_neg_integer()]
        ) :: WAManagedPhone.t() | nil
  defp pick_failover_candidate(wa_group_id, primary, exclude) do
    with_primary_excluded = if primary, do: Enum.uniq([primary.id | exclude]), else: exclude

    WAGroups.next_active_member(wa_group_id, with_primary_excluded) ||
      WAGroups.next_member(wa_group_id, with_primary_excluded) ||
      WAGroups.next_member(wa_group_id, exclude)
  end

  @spec finish_failover(
          WAGroup.t(),
          WAManagedPhone.t() | nil,
          WAManagedPhone.t(),
          atom()
        ) :: {:ok, WAManagedPhone.t(), :failover} | {:error, :promotion_failed}
  defp finish_failover(wa_group, primary, candidate, reason) do
    case promote(wa_group.id, candidate.id) do
      {:ok, _} ->
        if candidate.status != "active" do
          Logger.warning(
            "Sender: group #{wa_group.id} has no Maytapi-active phone; promoting #{candidate.phone} (status=#{candidate.status}) — status may be stale"
          )
        end

        notify_failover(wa_group, primary, candidate, reason)
        {:ok, candidate, :failover}

      {:error, err} ->
        Glific.log_error(
          "Sender: failed to promote wa_managed_phone #{candidate.id} for group #{wa_group.id}: #{inspect(err)}"
        )

        {:error, :promotion_failed}
    end
  end

  @spec notify_failover(
          WAGroup.t(),
          WAManagedPhone.t() | nil,
          WAManagedPhone.t(),
          atom()
        ) :: any()
  defp notify_failover(wa_group, primary, candidate, reason) do
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
      candidate_status: candidate.status
    })
  end

  @spec failover_message(WAGroup.t(), WAManagedPhone.t() | nil, WAManagedPhone.t()) :: String.t()
  defp failover_message(wa_group, %WAManagedPhone{id: id}, %WAManagedPhone{id: id} = candidate) do
    "Primary phone #{candidate.phone} for group #{wa_group.label} shows status '#{candidate.status}' but no backup is available; sending via primary anyway."
  end

  defp failover_message(wa_group, nil, candidate) do
    "Primary phone for group #{wa_group.label} is not set; switched to phone #{candidate.phone}."
  end

  defp failover_message(wa_group, primary, candidate) do
    "Primary phone #{primary.phone} for group #{wa_group.label} is unavailable; switched to phone #{candidate.phone}."
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
end
