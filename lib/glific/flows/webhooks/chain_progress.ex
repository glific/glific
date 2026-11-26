defmodule Glific.Flows.Webhooks.ChainProgress do
  @moduledoc """
  Tracks a multi-block Kaapi chain (speech-to-speech: STT -> LLM -> TTS) whose blocks each send
  a callback. Every block is appended to the webhook log (`response_json.intermediate_callbacks`),
  which doubles as the store the final callback reads the earlier outputs from, so it works across
  nodes. The gap between consecutive callbacks is emitted as a per-block latency.
  """

  alias Glific.{Flows.WebhookLog, Repo}
  alias Glific.Flows.Webhooks.Instrumentation

  @steps_key "intermediate_callbacks"
  @components %{1 => "stt", 2 => "llm", 3 => "tts"}

  @doc "True for a successful, non-final block of a chain: it must not resume the flow."
  @spec intermediate?(map(), map()) :: boolean()
  def intermediate?(%{"success" => true}, %{"block_index" => index, "total_blocks" => total})
      when is_integer(index) and is_integer(total),
      do: index < total

  def intermediate?(_result, _response), do: false

  @doc "Appends a non-final block to the webhook log and emits its latency."
  @spec record_intermediate(non_neg_integer(), map(), integer()) :: :ok
  def record_intermediate(organization_id, response, received_ts) do
    Repo.put_process_state(organization_id)
    record_block(response, received_ts, "success")
  end

  @doc """
  Appends the block that ended the chain (the audio, or the failure) to the log and emits its
  latency tagged with its status; a non-chain response is ignored.
  """
  @spec record_final(map(), map()) :: :ok
  def record_final(result, %{"call_type" => "voice_sts"} = response) do
    if result["success"] == true and response["success"] != false do
      record_block(response, response["callback_received_ts"], "success")
    else
      error = response["reason"] || result["error"] || response["message"]
      record_block(response, response["callback_received_ts"], "failure", error)
    end
  end

  def record_final(_result, _response), do: :ok

  @doc "The outputs of the earlier blocks, read back from the webhook log."
  @spec take(non_neg_integer(), non_neg_integer() | nil) :: map()
  def take(_organization_id, nil), do: %{}

  def take(_organization_id, log_id), do: log_id |> logged_steps() |> outputs()

  @doc """
  A speech-to-speech chain that failed after the LLM answered (the TTS block) still has a usable
  text answer: resume as a success with no audio instead of dropping it.
  """
  @spec fallback_to_text(map(), map()) :: map()
  def fallback_to_text(%{"success" => false}, %{"call_type" => "voice_sts"} = response) do
    {:ok, organization_id} = Glific.parse_maybe_integer(response["organization_id"])

    case take(organization_id, response["webhook_log_id"]) do
      %{"text" => text} = stash when is_binary(text) and text != "" ->
        Map.merge(response, %{
          "success" => true,
          "tts_failed" => true,
          "message" => text,
          "translated_text" => text,
          "transcript" => stash["stt"],
          "thread_id" => stash["thread_id"] || response["thread_id"],
          "media_url" => nil
        })

      _ ->
        response
    end
  end

  def fallback_to_text(_result, response), do: response

  @doc """
  Adds the chain's steps and outputs (answer, transcript, audio URL, conversation id) to the
  callback log message that replaces the log, so the final log row shows the whole result.
  """
  @spec keep_steps(non_neg_integer() | nil, map()) :: map()
  def keep_steps(nil, message), do: message

  def keep_steps(log_id, message) do
    case logged_steps(log_id) do
      [] ->
        message

      steps ->
        outputs = outputs(steps)

        message
        |> Map.put(:intermediate_callbacks, steps)
        |> Map.put(:transcript, outputs["stt"])
        |> Map.put(:media_url, outputs["media_url"])
        |> Map.put(:thread_id, outputs["thread_id"] || message[:thread_id])
        |> put_answer(outputs["text"])
    end
  end

  @spec put_answer(map(), String.t() | nil) :: map()
  defp put_answer(%{success: true} = message, answer) when is_binary(answer),
    do: Map.put(message, :message, answer)

  defp put_answer(message, _answer), do: message

  @spec outputs([map()]) :: map()
  defp outputs(steps) do
    Enum.reduce(steps, %{}, fn step, acc ->
      case {step["block_index"], step["status"]} do
        {_index, "failure"} ->
          acc

        {1, _status} ->
          Map.put(acc, "stt", step["message"])

        {2, _status} ->
          acc |> Map.put("text", step["message"]) |> put_present("thread_id", step["thread_id"])

        {3, _status} ->
          Map.put(acc, "media_url", step["message"])

        _ ->
          acc
      end
    end)
  end

  # Kaapi's final and failure callbacks carry no block index: they belong to the block after the
  # last one logged. A repeated delivery of a logged block is ignored (no second step or metric).
  @spec record_block(map(), integer() | nil, String.t(), String.t() | nil) :: :ok
  defp record_block(response, received_ts, status, error \\ nil)

  defp record_block(%{"webhook_log_id" => log_id} = response, received_ts, status, error)
       when is_integer(log_id) do
    with %WebhookLog{} = log <- Repo.get(WebhookLog, log_id),
         json = log.response_json || %{},
         steps = Map.get(json, @steps_key, []),
         response =
           Map.put(response, "block_index", response["block_index"] || length(steps) + 1),
         false <- Enum.any?(steps, &(&1["block_index"] == response["block_index"])) do
      latency_ms = block_latency_ms(steps, response, received_ts)
      track(response, latency_ms, status)

      step = %{
        "block_index" => response["block_index"],
        "component" => Map.get(@components, response["block_index"]),
        "output_type" => response["output_type"],
        "status" => status,
        "message" => if(status == "success", do: response["message"]),
        "error" => error,
        "thread_id" => response["thread_id"],
        "latency_ms" => latency_ms,
        "received_ts" => received_ts,
        "received_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      WebhookLog.update_webhook_log(log, %{
        response_json: Map.put(json, @steps_key, steps ++ [step])
      })
    end

    :ok
  end

  defp record_block(_response, _received_ts, _status, _error), do: :ok

  @spec block_latency_ms([map()], map(), integer() | nil) :: number() | nil
  defp block_latency_ms(steps, response, received_ts) do
    since =
      case List.last(steps) do
        %{"received_ts" => ts} when is_integer(ts) -> ts
        _ -> response["kaapi_dispatch_ts"]
      end

    if is_integer(since) and is_integer(received_ts) and received_ts >= since,
      do: (received_ts - since) / 1_000
  end

  @spec track(map(), number() | nil, String.t()) :: :ok
  defp track(_response, nil, _status), do: :ok

  defp track(response, latency_ms, status) do
    index = response["block_index"]

    Instrumentation.track_chain_block(
      response["webhook_name"],
      Map.get(@components, index, "block_#{index}"),
      latency_ms,
      response["audio_size_bucket"],
      status
    )
  end

  @spec logged_steps(non_neg_integer()) :: [map()]
  defp logged_steps(log_id) do
    case Repo.get(WebhookLog, log_id) do
      %{response_json: %{@steps_key => steps}} when is_list(steps) -> steps
      _ -> []
    end
  end

  @spec put_present(map(), String.t(), any()) :: map()
  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
