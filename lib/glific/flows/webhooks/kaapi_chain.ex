defmodule Glific.Flows.Webhooks.KaapiChain do
  @moduledoc """
  Tracks a Kaapi chain call (`/llm/chain/*`): a sequence of blocks (e.g. STT -> LLM -> TTS for
  speech-to-speech) where every block sends its own callback.

  The caller names the blocks in `request_metadata.chain_blocks`, which Kaapi echoes on every
  callback. Each block is appended to the webhook log (`response_json.intermediate_callbacks`),
  which doubles as the store the final callback reads earlier outputs from, so it works across
  nodes. The gap between consecutive callbacks is emitted as `kaapi_chain_latency`.
  """

  import Ecto.Query

  alias Glific.{Flows.WebhookLog, Repo}
  alias Glific.Flows.Webhooks.Instrumentation

  @steps_key "intermediate_callbacks"

  @doc "True for a successful, non-final block of a chain: it must not resume the flow."
  @spec intermediate?(map(), map()) :: boolean()
  def intermediate?(%{"success" => true}, %{"block_index" => index, "total_blocks" => total})
      when is_integer(index) and is_integer(total),
      do: index < total

  def intermediate?(_result, _response), do: false

  @doc "Appends a successful non-final block to the webhook log and emits its latency."
  @spec record_intermediate(map(), integer()) :: :ok | :duplicate | :error
  def record_intermediate(response, received_ts),
    do: record_block(response, received_ts, status: "success")

  @doc """
  Claims the block that ends the chain before any side effect (upload, resume): `:duplicate` when
  the chain already ended, so a repeated or concurrent final callback is dropped, and `:error` when
  the claim could not be saved. A response that is not part of a chain is always `:ok`.
  """
  @spec claim_final(map()) :: :ok | :duplicate | :error
  def claim_final(%{"chain_blocks" => blocks, "webhook_log_id" => log_id} = response)
      when is_list(blocks) and is_integer(log_id) do
    update_steps(log_id, fn steps ->
      index = response["block_index"] || length(steps) + 1

      if ended_or_logged?(steps, index) do
        :duplicate
      else
        {:ok,
         steps ++
           [
             %{
               "block_index" => index,
               "component" => component(response, index),
               "status" => "pending",
               "final" => true
             }
           ]}
      end
    end)
  end

  def claim_final(_response), do: :ok

  @doc """
  Fills in the block that ended the chain (its last output, or a failure) and emits its latency
  tagged with its status. A response that is not part of a chain is ignored.
  """
  @spec record_final(map(), map()) :: :ok | :duplicate | :error
  def record_final(result, %{"chain_blocks" => blocks} = response) when is_list(blocks) do
    if result["success"] == true and response["success"] != false do
      record_block(response, response["callback_received_ts"], status: "success", final: true)
    else
      error = response["reason"] || result["error"] || result["reason"] || response["message"]

      record_block(response, response["callback_received_ts"],
        status: "failure",
        error: error,
        final: true
      )
    end
  end

  def record_final(_result, _response), do: :ok

  @doc """
  The chain's outputs read back from the webhook log: the last text and audio outputs, the
  conversation id, and every successful block's output by component.
  """
  @spec outputs(non_neg_integer() | nil) :: map()
  def outputs(nil), do: %{"blocks" => %{}}
  def outputs(log_id), do: log_id |> logged_steps() |> steps_outputs()

  @doc """
  A chain that names a fallback block (`chain_fallback: "llm"`) and failed after that block
  succeeded resumes as a success carrying the block's output (`chain_degraded: true`) instead of
  dropping it. A failure before that block stays a failure.
  """
  @spec fallback_to_text(map(), map()) :: map()
  def fallback_to_text(%{"success" => false}, %{"chain_fallback" => component} = response)
      when is_binary(component) do
    case outputs(response["webhook_log_id"]) do
      %{"blocks" => %{^component => text}} when is_binary(text) and text != "" ->
        Map.merge(response, %{
          "success" => true,
          "chain_degraded" => true,
          "message" => text,
          "output_type" => "text"
        })

      _ ->
        response
    end
  end

  def fallback_to_text(_result, response), do: response

  @doc """
  Adds the chain's steps and outputs to the callback log message that replaces the log, so the
  final log row shows the whole result: the answer, `media_url`, `thread_id` and each block.
  """
  @spec append_callback_result(non_neg_integer() | nil, map()) :: map()
  def append_callback_result(nil, message), do: message

  def append_callback_result(log_id, message) do
    case logged_steps(log_id) do
      [] ->
        message

      steps ->
        outputs = steps_outputs(steps)

        message
        |> Map.put(:intermediate_callbacks, steps)
        |> Map.put(:outputs, outputs["blocks"])
        |> Map.put(:media_url, outputs["audio"])
        |> Map.put(:thread_id, outputs["thread_id"] || message[:thread_id])
        |> put_answer(outputs["text"])
    end
  end

  @spec put_answer(map(), String.t() | nil) :: map()
  defp put_answer(%{success: true} = message, answer) when is_binary(answer),
    do: Map.put(message, :message, answer)

  defp put_answer(message, _answer), do: message

  @spec steps_outputs([map()]) :: map()
  defp steps_outputs(steps) do
    # Chain order, not arrival order: the last text output must be the last text block.
    steps
    |> Enum.filter(&(&1["status"] == "success"))
    |> Enum.sort_by(& &1["block_index"])
    |> Enum.reduce(%{"blocks" => %{}}, fn step, acc ->
      acc
      |> put_in(["blocks", step["component"]], step["message"])
      |> put_output(step["output_type"], step["message"])
      |> put_present("thread_id", step["thread_id"])
    end)
  end

  @spec put_output(map(), String.t() | nil, any()) :: map()
  defp put_output(acc, type, message) when type in ["text", "audio"],
    do: put_present(acc, type, message)

  defp put_output(acc, _type, _message), do: acc

  # Kaapi's final and failure callbacks carry no block index: they belong to the block after the
  # last one logged. A block claimed by `claim_final/1` is filled in place; otherwise, once the
  # chain has ended or the block is logged, a repeated delivery is ignored (no second step or
  # metric), so a retried index-less callback is not counted twice.
  @spec record_block(map(), integer() | nil, keyword()) :: :ok | :duplicate | :error
  defp record_block(%{"webhook_log_id" => log_id} = response, received_ts, opts)
       when is_integer(log_id) do
    final? = Keyword.get(opts, :final, false)

    update_steps(log_id, fn steps ->
      case final? && Enum.find_index(steps, &(&1["status"] == "pending")) do
        claimed when not is_integer(claimed) ->
          index = response["block_index"] || length(steps) + 1

          if ended_or_logged?(steps, index),
            do: :duplicate,
            else: {:ok, steps ++ [build_step(response, index, steps, received_ts, opts)]}

        position ->
          {before, [claimed | _rest]} = Enum.split(steps, position)
          step = build_step(response, claimed["block_index"], before, received_ts, opts)
          {:ok, before ++ [step]}
      end
    end)
  end

  defp record_block(_response, _received_ts, _opts), do: :ok

  @spec build_step(map(), pos_integer(), [map()], integer() | nil, keyword()) :: map()
  defp build_step(response, index, previous_steps, received_ts, opts) do
    status = Keyword.fetch!(opts, :status)
    component = component(response, index)
    latency_ms = block_latency_ms(previous_steps, response, received_ts)
    track(response, component, latency_ms, status)

    %{
      "block_index" => index,
      "component" => component,
      "status" => status,
      "output_type" => response["output_type"],
      "message" => if(status == "success", do: response["message"]),
      "error" => opts[:error],
      "final" => Keyword.get(opts, :final, false),
      "thread_id" => response["thread_id"],
      "latency_ms" => latency_ms,
      "received_ts" => received_ts,
      "received_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @spec ended_or_logged?([map()], pos_integer()) :: boolean()
  defp ended_or_logged?(steps, index),
    do: Enum.any?(steps, &(&1["final"] == true or &1["block_index"] == index))

  # The row lock serialises concurrent callbacks of one chain, so two deliveries can't both read
  # the steps before either writes.
  @spec update_steps(non_neg_integer(), ([map()] -> {:ok, [map()]} | :duplicate)) ::
          :ok | :duplicate | :error
  defp update_steps(log_id, fun) do
    Repo.transaction(fn ->
      with %WebhookLog{} = log <-
             WebhookLog |> where([l], l.id == ^log_id) |> lock("FOR UPDATE") |> Repo.one(),
           json = log.response_json || %{},
           {:ok, steps} <- fun.(Map.get(json, @steps_key, [])),
           {:ok, _log} <-
             WebhookLog.update_webhook_log(log, %{
               response_json: Map.put(json, @steps_key, steps)
             }) do
        :ok
      else
        :duplicate -> :duplicate
        nil -> Repo.rollback(:webhook_log_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, outcome} ->
        outcome

      {:error, reason} ->
        Glific.log_error(
          "Kaapi chain step not saved for webhook_log_id=#{log_id}: " <>
            Glific.SafeLog.safe_inspect(reason)
        )

        :error
    end
  end

  @spec component(map(), pos_integer()) :: String.t()
  defp component(%{"chain_blocks" => blocks}, index) when is_list(blocks),
    do: Enum.at(blocks, index - 1) || "block_#{index}"

  defp component(_response, index), do: "block_#{index}"

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

  @spec track(map(), String.t(), number() | nil, String.t()) :: :ok
  defp track(_response, _component, nil, _status), do: :ok

  defp track(response, component, latency_ms, status) do
    Instrumentation.track_chain_block(latency_ms, %{
      chain: response["call_type"],
      webhook_name: response["webhook_name"],
      component: component,
      size_bucket: response["audio_size_bucket"],
      status: status
    })
  end

  @spec logged_steps(non_neg_integer() | nil) :: [map()]
  defp logged_steps(nil), do: []

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
