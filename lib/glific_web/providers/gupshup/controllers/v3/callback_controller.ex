defmodule GlificWeb.Providers.Gupshup.Controllers.V3.CallbackController do
  @moduledoc """
  Single entry point for Gupshup V3 (Meta format) callbacks. The payload is unpacked once
  into the values of entry[].changes[], and each value is handled by what it carries:
  message statuses or WhatsApp form responses.
  """
  use GlificWeb, :controller

  require Logger

  alias Glific.Communications
  alias Glific.Providers.Gupshup
  alias Glific.Providers.Gupshup.Instrumentation
  alias Glific.SafeLog

  @bsp_statuses %{
    "enqueued" => :enqueued,
    "sent" => :sent,
    "delivered" => :delivered,
    "read" => :read,
    "failed" => :error
  }

  @doc """
  Handles every change in a V3 callback
  """
  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(conn, %{"entry" => entries}) do
    entries
    |> change_values()
    |> Enum.each(&handle_change(conn, &1))

    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @spec change_values(list()) :: [map()]
  defp change_values(entries) do
    for %{"changes" => changes} when is_list(changes) <- entries,
        %{"value" => %{} = value} <- changes,
        do: value
  end

  @spec handle_change(Plug.Conn.t(), map()) :: :ok
  defp handle_change(conn, %{"statuses" => statuses}) when is_list(statuses),
    do: Enum.each(statuses, &update_status(conn, &1))

  defp handle_change(
         conn,
         %{
           "messages" => [%{"interactive" => %{"type" => "nfm_reply"}} = message | _],
           "contacts" => [contact | _]
         }
       ) do
    organization_id = conn.assigns[:organization_id]

    {message, contact}
    |> Gupshup.Message.receive_whatsapp_form_response()
    |> Map.put(:organization_id, organization_id)
    |> put_in([:sender, :contact_type], "WABA")
    |> Communications.Message.receive_message(:whatsapp_form_response)

    Instrumentation.track_receive("whatsapp_form_response handler", organization_id)
  end

  defp handle_change(_conn, value) do
    keys = Map.keys(value)
    Logger.info("Unhandled Gupshup V3 callback change with keys: #{SafeLog.safe_inspect(keys)}")
  end

  @spec update_status(Plug.Conn.t(), map()) :: :ok
  defp update_status(conn, %{"status" => meta_status} = status) do
    with {:ok, bsp_status} <- Map.fetch(@bsp_statuses, meta_status),
         bsp_message_id when is_binary(bsp_message_id) <- status["gs_id"] || status["id"] do
      {error_code, _error_reason} = error = status_error(status)
      status_params = bsp_status_params(status, bsp_status, error)

      Communications.Message.update_bsp_status(bsp_message_id, bsp_status, status_params)

      Instrumentation.track_status(bsp_status, conn.assigns[:organization_id],
        error_code: error_code
      )
    else
      _ -> :ok
    end
  end

  defp update_status(_conn, _status), do: :ok

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
