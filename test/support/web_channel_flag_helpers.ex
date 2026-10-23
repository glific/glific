defmodule Glific.WebChannelFlagHelpers do
  @moduledoc """
  Shared `:web_channel_enabled` FunWithFlags setup, used by every web channel test — channel and
  REST alike. FunWithFlags' ETS cache is not sandbox-scoped and can carry a previous test's
  enabled flag into this one; resetting on the way in caught roughly one run in five failing
  before this existed (see the original inline version this replaces in
  `web_channel_auth_controller_test.exs`).
  """

  alias FunWithFlags.Store.Cache
  alias Glific.{Partners, Repo, WebChannel.JwtSecret}

  @shortcode "web_channel"

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

  @doc """
  Gives the organization an active `web_channel` credential, the organization's own half of the
  switch — without it the channel is off however the flag is set. Upserts, so a test may call it
  again to set the branding keys.
  """
  @spec activate_web_channel(non_neg_integer(), map(), map()) :: :ok
  def activate_web_channel(organization_id \\ 1, keys \\ %{}, secrets \\ %{}) do
    case Partners.get_credential(%{organization_id: organization_id, shortcode: @shortcode}) do
      {:ok, credential} ->
        secrets = Map.merge(credential.secrets || %{}, secrets)
        Partners.update_credential(credential, %{keys: keys, secrets: secrets, is_active: true})

      _not_yet ->
        Partners.create_credential(%{
          organization_id: organization_id,
          shortcode: @shortcode,
          keys: keys,
          secrets: secrets,
          is_active: true
        })
    end

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
    activate_web_channel(organization_id)
    FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: organization_id})
    organization_id |> Partners.organization() |> Partners.fill_cache()

    try do
      fun.()
    after
      reset_web_channel_flag(organization_id)
    end
  end

  @doc """
  Runs `fun` with the web channel on for `organization_id` and `secrets`
  (e.g. `jwt_signature_secrets(["..."])`) in its credential, restoring the flag after.
  """
  @spec with_web_channel_secrets(non_neg_integer(), map(), (-> any())) :: any()
  def with_web_channel_secrets(organization_id \\ 1, secrets, fun) do
    activate_web_channel(organization_id, %{}, secrets)
    FunWithFlags.enable(:web_channel_enabled, for_actor: %{organization_id: organization_id})
    organization_id |> Partners.organization() |> Partners.fill_cache()

    try do
      fun.()
    after
      reset_web_channel_flag(organization_id)
    end
  end

  @doc """
  Empties the organization's `web_channel` credential secrets, bypassing the auto-creation that
  saving an active credential does, to put it in the state of an organization with no secret.
  """
  @spec remove_web_channel_secret(non_neg_integer()) :: :ok
  def remove_web_channel_secret(organization_id \\ 1) do
    {:ok, credential} =
      Partners.get_credential(%{organization_id: organization_id, shortcode: @shortcode})

    # Past the changeset, which refuses to remove a saved secret.
    {:ok, _credential} = credential |> Ecto.Changeset.change(%{secrets: %{}}) |> Repo.update()

    organization = Partners.organization(organization_id)
    Partners.remove_organization_cache(organization.id, organization.shortcode)
    :ok
  end

  @doc """
  The organization's current web channel signing secret.
  """
  @spec web_channel_secret(non_neg_integer()) :: String.t()
  def web_channel_secret(organization_id \\ 1) do
    {:ok, secret} = JwtSecret.fetch(organization_id)
    secret
  end

  @doc """
  The credential secrets holding `secrets` as the organization's named JWT signature secrets.
  """
  @spec jwt_signature_secrets([String.t()]) :: map()
  def jwt_signature_secrets(secrets) do
    entries =
      secrets
      |> Enum.with_index(1)
      |> Enum.map(fn {secret, position} ->
        %{"name" => "secret #{position}", "secret" => secret}
      end)

    %{"jwt_signature_secrets" => entries}
  end
end
