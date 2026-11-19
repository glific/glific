defmodule Glific.Providers.Gupshup.V3.Handlers.Status do
  @moduledoc """
  Updates the BSP status of the messages in a Gupshup V3 statuses change.
  """

  @behaviour Glific.Providers.Gupshup.V3.Handler

  alias Glific.Communications
  alias Glific.Providers.Gupshup.Instrumentation

  @bsp_statuses %{
    "enqueued" => :enqueued,
    "sent" => :sent,
    "delivered" => :delivered,
    "read" => :read,
    "failed" => :error
  }

  @impl true
  @spec handle(map(), non_neg_integer()) :: :ok
  def handle(%{"statuses" => statuses}, organization_id),
    do: Enum.each(statuses, &update_status(&1, organization_id))

  @spec update_status(map(), non_neg_integer()) :: :ok
  defp update_status(%{"status" => meta_status} = status, organization_id) do
    with {:ok, bsp_status} <- Map.fetch(@bsp_statuses, meta_status),
         bsp_message_id when is_binary(bsp_message_id) <- status["gs_id"] do
      {error_code, _error_reason} = error = status_error(status)
      status_params = bsp_status_params(status, bsp_status, error)

      status_changed? =
        Communications.Message.update_bsp_status(
          bsp_message_id,
          bsp_status,
          status_params,
          "meta"
        )

      if status_changed?,
        do: Instrumentation.track_status(bsp_status, organization_id, error_code: error_code),
        else: :ok
    else
      _ -> :ok
    end
  end

  defp update_status(_status, _organization_id), do: :ok

  # Communications.Message reads a failure's error code from the V2 payload.payload.code shape
  @spec bsp_status_params(map(), atom(), {term(), String.t() | nil}) :: map()
  defp bsp_status_params(status, :error, {error_code, error_reason}),
    do:
      Map.put(status, "payload", %{
        "payload" => %{"code" => error_code, "reason" => error_reason}
      })

  defp bsp_status_params(status, _bsp_status, _error), do: status

  # Meta's format nests the error in an errors array, while Gupshup's passthrough V3
  # puts code and reason directly on the status
  @spec status_error(map()) :: {term(), String.t() | nil}
  defp status_error(%{"errors" => [%{} = error | _]}),
    do: {normalize_error_code(error["code"]), error["title"]}

  defp status_error(%{"code" => code} = status),
    do: {normalize_error_code(code), status["reason"]}

  defp status_error(_status), do: {nil, nil}

  @spec normalize_error_code(term()) :: term()
  defp normalize_error_code(code) when is_binary(code) do
    case Integer.parse(code) do
      {integer_code, ""} -> integer_code
      _ -> code
    end
  end

  defp normalize_error_code(code), do: code
end
