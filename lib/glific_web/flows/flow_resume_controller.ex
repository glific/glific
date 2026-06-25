defmodule GlificWeb.Flows.FlowResumeController do
  @moduledoc """
  Receives callbacks from 3rd-party async webhooks (Kaapi STT/TTS, filesearch,
  voice unified-LLM) and resumes the parked flow.

  This controller is intentionally thin: it pulls the organization context off
  the connection, parses/normalises the callback body, and hands the actual
  resume work to `Glific.Flows.Webhook` — the inbound counterpart of the
  webhook execute/perform path. All validation, logging, telemetry and flow
  resumption live there.
  """

  use GlificWeb, :controller
  use Publicist

  alias Glific.Flows.Webhook

  @doc """
  Resume a flow after an async webhook (e.g. Kaapi STT/TTS) calls back.
  """
  @spec flow_resume(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    # Parse + TTS upload run in the request process (not the supervised task) to
    # avoid transferring large audio binaries between processes.
    # https://elixirmerge.com/p/the-impact-of-data-transfer-on-performance-in-elixirs-task-async
    response = result |> Webhook.parse_callback_response() |> Webhook.maybe_upload_tts_audio()

    run_supervised(fn -> Webhook.resume(organization_id, result, response) end)

    json(conn, "")
  end

  @doc """
  Callback for voice unified LLM calls. Resumes the flow after voice
  post-processing (NMT + TTS) shapes the Kaapi response.
  """
  @spec voice_flow_resume(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def voice_flow_resume(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    response = Webhook.parse_callback_response(result)

    run_supervised(fn -> Webhook.voice_resume(organization_id, result, response) end)

    json(conn, "")
  end

  @spec run_supervised((-> any())) :: :ok
  defp run_supervised(fun) do
    case Task.Supervisor.start_child(Glific.TaskSupervisor, fn ->
           run_supervised_task(fun)
         end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Glific.log_exception(%RuntimeError{
          message: "Failed to start flow_resume supervised task: #{inspect(reason)}"
        })

        :ok
    end
  end

  @spec run_supervised_task((-> any())) :: :ok
  defp run_supervised_task(fun) do
    try do
      fun.()
    rescue
      exception ->
        Glific.log_exception(exception)
    end

    :ok
  end
end
