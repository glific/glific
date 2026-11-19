defmodule Glific.ErrorLogCounter do
  @moduledoc """
  A `:logger` handler that counts every error-or-worse log event in AppSignal as
  `error_log_count`, tagged with the emitting process's `org_id` metadata.

  Process crash reports are counted too, since they are logged at error level by the crashing
  process. Events logged without an organization are tagged `"unknown"`.
  """

  @handler_id :glific_error_log_counter
  @metric "error_log_count"

  @doc "Attaches the handler to `:logger`; safe to call more than once."
  @spec attach() :: :ok | {:error, term()}
  def attach do
    if @handler_id in :logger.get_handler_ids(),
      do: :ok,
      else: :logger.add_handler(@handler_id, __MODULE__, %{level: :error})
  end

  @doc "`:logger` handler callback."
  @spec log(:logger.log_event(), :logger.handler_config()) :: :ok
  def log(%{meta: meta}, _config) do
    Appsignal.increment_counter(@metric, 1, %{organization_id: organization_tag(meta)})
    :ok
  rescue
    # :logger permanently removes a handler whose callback raises; never let that happen.
    _ -> :ok
  end

  @spec organization_tag(map()) :: String.t()
  defp organization_tag(%{org_id: org_id}) when not is_nil(org_id), do: to_string(org_id)
  defp organization_tag(_meta), do: "unknown"
end
