defmodule GlificWeb.Schema.Middleware.RequireFeatureFlag do
  @moduledoc """
  Middleware that checks if a given feature flag is enabled for the current user's organization.
  If the flag is disabled, returns a 403-style error and halts resolution.
  Configuration: `{flag_atom, error_message}` e.g. `{:ai_evaluations, "AI Evaluations feature is not enabled for the organization."}`
  """
  @behaviour Absinthe.Middleware

  @doc """
  Receives resolution and config `{flag, message}`. Uses `resolution.context.current_user.organization_id`
  to check the flag. If enabled, returns resolution unchanged; otherwise puts error result.
  """
  @spec call(Absinthe.Resolution.t(), {atom(), String.t()}) :: Absinthe.Resolution.t()
  def call(resolution, {flag, message}) do
    with %{organization_id: organization_id} <- get_current_user(resolution),
         true <- FunWithFlags.enabled?(flag, for: %{organization_id: organization_id}) do
      resolution
    else
      _ ->
        resolution
        |> put_forbidden_in_context()
        |> Absinthe.Resolution.put_result({:error, "#{message} is not enabled for the organization."})
    end
  end

  defp get_current_user(%{context: %{current_user: user}}) when not is_nil(user), do: user
  defp get_current_user(_), do: nil

  defp put_forbidden_in_context(resolution) do
    %{resolution | context: Map.put(resolution.context, :feature_flag_forbidden, true)}
  end
end
