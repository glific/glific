defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventController do
  @moduledoc """
  Dedicated controller to handle all the message status requests like read, delivered etc..
  """
  use GlificWeb, :controller

  alias Glific.{
    Communications,
    Providers.Gupshup.Instrumentation
  }

  @meta_statuses %{
    "enqueued" => :enqueued,
    "sent" => :sent,
    "delivered" => :delivered,
    "read" => :read,
    "failed" => :error
  }

  @doc """
  Default handle for all message event callbacks
  """
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Message status when the message has been sent to gupshup
  """
  @spec enqueued(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def enqueued(conn, params),
    do: update_status(conn, params, :enqueued)

  @doc """
  Message status when gupshup could not send the message to whats app
  """
  @spec failed(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def failed(conn, params),
    do: update_status(conn, params, :error)

  @doc """
  Message has been sent to whats app via Gupshup
  """
  @spec sent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sent(conn, params),
    do: update_status(conn, params, :sent)

  @doc """
  Message has been delivered to whats app
  """
  @spec delivered(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delivered(conn, params),
    do: update_status(conn, params, :delivered)

  @doc """
  Message has been read by the beneficiary
  """
  @spec read(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def read(conn, params),
    do: update_status(conn, params, :read)

  @doc """
  Message statuses sent in the Gupshup V3 (Meta) callback format
  """
  @spec statuses(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def statuses(conn, %{"entry" => entries} = params) do
    entries
    |> meta_statuses()
    |> Enum.each(&update_meta_status(conn, &1))

    handler(conn, params, "Statuses updated")
  end

  @spec meta_statuses(list()) :: list()
  defp meta_statuses(entries) do
    for %{"changes" => changes} when is_list(changes) <- entries,
        %{"value" => %{"statuses" => statuses}} when is_list(statuses) <- changes,
        status <- statuses,
        do: status
  end

  @spec update_meta_status(Plug.Conn.t(), map()) :: :ok
  defp update_meta_status(conn, %{"status" => meta_status} = status) do
    with {:ok, bsp_status} <- Map.fetch(@meta_statuses, meta_status),
         bsp_message_id when is_binary(bsp_message_id) <- status["gs_id"] || status["id"] do
      error = meta_error(status)
      error_code = error["code"]

      # process_errors/3 reads the error code from the V2 payload.payload.code shape
      status_params =
        Map.put(status, "payload", %{
          "payload" => %{"code" => error_code, "reason" => error["title"]}
        })

      Communications.Message.update_bsp_status(bsp_message_id, bsp_status, status_params)

      Instrumentation.track_status(bsp_status, conn.assigns[:organization_id],
        error_code: error_code
      )
    else
      _ -> :ok
    end
  end

  defp update_meta_status(_conn, _status), do: :ok

  @spec meta_error(map()) :: map()
  defp meta_error(%{"errors" => [%{} = error | _]}), do: error
  defp meta_error(_status), do: %{}

  # Updates the provider message status based on provider message id
  @spec update_status(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp update_status(conn, params, status) do
    bsp_message_id = get_in(params, ["payload", "gsId"]) || get_in(params, ["payload", "id"])
    Communications.Message.update_bsp_status(bsp_message_id, status, params)

    Instrumentation.track_status(status, conn.assigns[:organization_id],
      error_code: get_in(params, ["payload", "payload", "code"])
    )

    handler(conn, params, "Status updated")
  end
end
