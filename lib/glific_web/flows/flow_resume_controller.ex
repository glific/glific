defmodule GlificWeb.Flows.FlowResumeController do
  @moduledoc """
  Receives callbacks from 3rd-party async webhooks (Kaapi STT/TTS, filesearch, voice unified-LLM)
  and resumes the parked flow. Stays thin: parses the callback and hands off to
  `Glific.Flows.Webhook` for validation, logging, telemetry and flow resumption.
  """

  use GlificWeb, :controller
  use Publicist

  alias Glific.{Flows.Webhook, Repo}

  @doc """
  Resume a flow after any async webhook calls back. Every Kaapi node (STT, TTS, filesearch-gpt,
  voice) posts back to `/webhook/flow_resume` — `Webhook.resume` dispatches to the node's
  `handle_callback/3`.
  """
  @spec flow_resume(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    # Stamp arrival before parse/upload and the task hop, so the voice filesearch leg
    # (arrival - dispatch) reflects true arrival rather than that overhead.
    callback_received_ts = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    parsed = Webhook.parse_callback_response(result)

    # The signature is checked here, ahead of the TTS upload, so an unsigned callback cannot make
    # us decode an arbitrary base64 payload and push it to GCS. Rejections still answer 200 — the
    # caller learns nothing, and Kaapi has no retry to trigger.
    if Webhook.valid_callback?(organization_id, parsed),
      do: resume(conn, organization_id, result, parsed, callback_received_ts),
      else: json(conn, "")
  end

  # Kaapi times out waiting on this response, so the TTS upload — a GCS round trip on a
  # multi-megabyte payload — runs in the supervised task and Kaapi gets its 200 straight away.
  # The task sets its own tenant context: it runs outside the request process, so the plug's
  # organization_id is not in scope, and the GCS error path writes org-scoped rows.
  # TODO: move maybe_upload_tts_audio/1 out of this controller — it's TTS-specific and
  # breaches the thin/generic contract; revisit during the speech-to-speech integration.
  @spec resume(Plug.Conn.t(), non_neg_integer(), map(), map(), integer()) :: Plug.Conn.t()
  defp resume(conn, organization_id, result, parsed, callback_received_ts) do
    run_supervised(fn ->
      Repo.put_process_state(organization_id)

      response =
        parsed
        |> Webhook.maybe_upload_tts_audio()
        |> Map.put("callback_received_ts", callback_received_ts)

      Webhook.resume(organization_id, result, response)
    end)

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
