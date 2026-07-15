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
  Resume a flow after any async webhook (Kaapi STT/TTS, filesearch, voice unified-LLM) calls
  back. Both the `/flow_resume` and `/voice_flow_resume` routes land here — `Webhook.resume`
  dispatches to the node's `callback/3` by `webhook_name`, so voice post-processing (NMT+TTS)
  and the plain pass-through nodes share one path.
  """
  @spec flow_resume(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    # Parse + TTS upload run in the request process (not the supervised task) to
    # avoid transferring large audio binaries between processes.
    # https://elixirmerge.com/p/the-impact-of-data-transfer-on-performance-in-elixirs-task-async
    # `maybe_upload_tts_audio/1` is a no-op unless the callback carries TTS audio, so it is
    # harmless on the voice / STT / filesearch callbacks that also route here.
    # TODO: Move `Webhook.maybe_upload_tts_audio/1` out of this controller. It is
    # TTS-specific and breaches this module's contract as a thin, generic resume
    # handler, so it belongs in a more appropriate place. To be addressed during the
    # speech-to-speech integration.
    response = result |> Webhook.parse_callback_response() |> Webhook.maybe_upload_tts_audio()

    run_supervised(fn -> Webhook.resume(organization_id, result, response) end)

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
          message:
            "Failed to start flow_resume supervised task: #{Glific.SafeLog.safe_inspect(reason)}"
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
