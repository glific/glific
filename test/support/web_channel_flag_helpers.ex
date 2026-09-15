defmodule Glific.WebChannelFlagHelpers do
  @moduledoc """
  Shared `:web_channel_enabled` FunWithFlags setup, used by every web channel test — channel and
  REST alike. FunWithFlags' ETS cache is not sandbox-scoped and can carry a previous test's
  enabled flag into this one; resetting on the way in caught roughly one run in five failing
  before this existed (see the original inline version this replaces in
  `web_channel_auth_controller_test.exs`).
  """

  alias FunWithFlags.Store.Cache
  alias Glific.Partners

  @doc """
  Disables `:web_channel_enabled` for `organization_id` and refills the org cache.
  """
  @spec reset_web_channel_flag(non_neg_integer()) :: :ok
  def reset_web_channel_flag(organization_id \\ 1) do
    FunWithFlags.disable(:web_channel_enabled, for_actor: %{organization_id: organization_id})
    Cache.flush()
    organization_id |> Partners.organization() |> Partners.fill_cache()
    :ok
  end

  # try/after rather than on_exit: the flag write needs the process owning this test's sandbox
  # connection, and on_exit runs after that process has gone.
  @doc """
  Runs `fun` with `:web_channel_enabled` turned on for `organization_id`, restoring it after.
  """
  @spec with_web_channel_enabled(non_neg_integer(), (-> any())) :: any()
  def with_web_channel_enabled(organization_id \\ 1, fun) do
    FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: organization_id})
    organization_id |> Partners.organization() |> Partners.fill_cache()

    try do
      fun.()
    after
      reset_web_channel_flag(organization_id)
    end
  end
end
