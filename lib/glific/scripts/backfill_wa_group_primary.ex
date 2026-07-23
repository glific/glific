defmodule Glific.Scripts.BackfillWAGroupPrimary do
  @moduledoc """
  One-off backfill for `wa_groups_phones.is_primary` on groups that have
  memberships but no row currently marked `is_primary: true`. Restores the
  Phase 1 invariant for production data that drifted in the window between
  Phase 1 backfill and Phase 3 deploy.

  ## What it does (per Case A group)

  Promotes the phone in `wa_groups.wa_managed_phone_id` (legacy column)
  to `is_primary: true`, provided that phone has an `is_active: true`
  membership row in the group. This restores Phase 1 intent without
  changing operational behaviour: the legacy phone is the one that was
  already being used for the group; we're just correctly flagging it.

  Groups whose legacy phone is no longer an active member are logged
  and skipped — they need separate handling (re-sync, admin promotion).

  ## Run from IEx (`gigalixir remote_console`)

      iex> Glific.Scripts.BackfillWAGroupPrimary.run_all()
      [%{org_id: 1, ...}, ...]

      # or for a single org
      iex> Glific.Scripts.BackfillWAGroupPrimary.run(organization_id)
      %{groups_examined: 198, fixed_via_legacy: 198, unfixable: 0}

  Idempotent — once a group has any `is_primary: true` row, re-running
  skips it.
  """

  import Ecto.Query
  require Logger

  alias Glific.{
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Partners,
    Repo,
    SafeLog
  }

  @typedoc "Result counters per org run."
  @type result :: %{
          org_id: non_neg_integer(),
          groups_examined: non_neg_integer(),
          fixed_via_legacy: non_neg_integer(),
          unfixable: non_neg_integer()
        }

  @doc """
  Run the backfill across every organization in the system.
  """
  @spec run_all() :: [result()]
  def run_all do
    Partners.list_organizations()
    |> Enum.map(&run(&1.id))
  end

  @doc """
  Run the backfill for a single organization.
  """
  @spec run(non_neg_integer()) :: result()
  def run(org_id) do
    Repo.put_organization_id(org_id)

    groups = list_groups_without_primary(org_id)

    base = %{
      org_id: org_id,
      groups_examined: length(groups),
      fixed_via_legacy: 0,
      unfixable: 0
    }

    result =
      Enum.reduce(groups, base, fn wa_group, acc ->
        case fix_one(wa_group) do
          :ok -> Map.update!(acc, :fixed_via_legacy, &(&1 + 1))
          :skip -> Map.update!(acc, :unfixable, &(&1 + 1))
        end
      end)

    Logger.info("BackfillWAGroupPrimary org=#{org_id} #{SafeLog.safe_inspect(result)}")
    result
  end

  @spec list_groups_without_primary(non_neg_integer()) :: [WAGroup.t()]
  defp list_groups_without_primary(org_id) do
    from(wa_group in WAGroup,
      join: membership in WAGroupPhone,
      on: membership.wa_group_id == wa_group.id,
      left_join: primary in WAGroupPhone,
      on: primary.wa_group_id == wa_group.id and primary.is_primary == true,
      where: wa_group.organization_id == ^org_id and is_nil(primary.id),
      distinct: wa_group.id
    )
    |> Repo.all()
  end

  @spec fix_one(WAGroup.t()) :: :ok | :skip
  defp fix_one(%WAGroup{} = wa_group) do
    case legacy_active_membership_phone(wa_group) do
      nil ->
        Logger.warning(
          "BackfillWAGroupPrimary: skipping wa_group #{wa_group.id} (org #{wa_group.organization_id}) — legacy phone has no active membership"
        )

        :skip

      phone ->
        case WAGroups.set_primary_phone(wa_group.id, phone.id) do
          {:ok, _} ->
            :ok

          {:error, err} ->
            Logger.warning(
              "Maytapi primary change failed (backfill): wa_group=#{wa_group.id} phone=#{phone.id} reason=#{SafeLog.safe_inspect(err)}"
            )

            :skip
        end
    end
  end

  @spec legacy_active_membership_phone(WAGroup.t()) :: Glific.WAGroup.WAManagedPhone.t() | nil
  defp legacy_active_membership_phone(%WAGroup{wa_managed_phone_id: nil}), do: nil

  defp legacy_active_membership_phone(%WAGroup{} = wa_group) do
    case Repo.get_by(WAGroupPhone, %{
           wa_group_id: wa_group.id,
           wa_managed_phone_id: wa_group.wa_managed_phone_id,
           is_active: true
         }) do
      nil -> nil
      wa_group_phone -> Repo.preload(wa_group_phone, :wa_managed_phone).wa_managed_phone
    end
  end
end
