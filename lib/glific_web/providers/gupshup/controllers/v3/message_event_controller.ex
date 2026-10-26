defmodule GlificWeb.Providers.Gupshup.Controllers.V3.MessageEventController do
  @moduledoc """
  Handles message status callbacks sent in the Gupshup V3 (Meta) format,
  where statuses arrive under entry[].changes[].value.statuses[].
  """
  use GlificWeb, :controller

  alias Glific.Communications
  alias Glific.Providers.Gupshup.Instrumentation

  @bsp_statuses %{
    "enqueued" => :enqueued,
    "sent" => :sent,
    "delivered" => :delivered,
    "read" => :read,
    "failed" => :error
  }

  @doc """
  Updates the status of every message in a V3 status callback
  """
  @spec statuses(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def statuses(conn, %{"entry" => entries}) do
    entries
    |> meta_statuses()
    |> Enum.each(&update_meta_status(conn, &1))

    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @spec meta_statuses(list()) :: [map()]
  defp meta_statuses(entries) do
    for %{"changes" => changes} when is_list(changes) <- entries,
        %{"value" => %{"statuses" => statuses}} when is_list(statuses) <- changes,
        %{} = status <- statuses,
        do: status
  end

  @spec update_meta_status(Plug.Conn.t(), map()) :: :ok
  defp update_meta_status(conn, %{"status" => meta_status} = status) do
    with {:ok, bsp_status} <- Map.fetch(@bsp_statuses, meta_status),
         bsp_message_id when is_binary(bsp_message_id) <- status["gs_id"] || status["id"] do
      {error_code, _error_reason} = error = meta_error(status)
      status_params = bsp_status_params(status, bsp_status, error)

      Communications.Message.update_bsp_status(bsp_message_id, bsp_status, status_params)

      Instrumentation.track_status(bsp_status, conn.assigns[:organization_id],
        error_code: error_code
      )
    else
      _ -> :ok
    end
  end

  defp update_meta_status(_conn, _status), do: :ok

  # process_errors/3 reads the error code from the V2 payload.payload.code shape
  @spec bsp_status_params(map(), atom(), {term(), String.t() | nil}) :: map()
  defp bsp_status_params(status, :error, {error_code, error_reason}),
    do:
      Map.put(status, "payload", %{
        "payload" => %{"code" => error_code, "reason" => error_reason}
      })

  defp bsp_status_params(status, _bsp_status, _error), do: status

  # Meta's format nests the error in an errors array, while Gupshup's passthrough V3
  # puts code and reason directly on the status
  @spec meta_error(map()) :: {term(), String.t() | nil}
  defp meta_error(%{"errors" => [%{} = error | _]}),
    do: {normalize_error_code(error["code"]), error["title"]}

  defp meta_error(%{"code" => code} = status),
    do: {normalize_error_code(code), status["reason"]}

  defp meta_error(_status), do: {nil, nil}

  @spec normalize_error_code(term()) :: term()
  defp normalize_error_code(code) when is_binary(code) do
    case Integer.parse(code) do
      {integer_code, ""} -> integer_code
      _ -> code
    end
  end

  defp normalize_error_code(code), do: code
end
