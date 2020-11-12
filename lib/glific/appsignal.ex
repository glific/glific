defmodule Glific.Appsignal do
  @moduledoc """
  A simple interface that connect Oban job status to Appsignal
  """

  alias Appsignal.Error
  alias Appsignal.Transaction

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:oban, event], measurement, meta, _) when event in [:success, :failure] do
    transaction = record_event(measurement, meta)

    if event == :failure && meta.attempt >= meta.max_attempts do
      {reason, message, stack} = normalize_error(meta)
      Transaction.set_error(transaction, reason, message, stack)
    end

    Transaction.complete(transaction)
  end

  defp record_event(measurement, meta) do
    metadata = %{"id" => meta.id, "queue" => meta.queue, "attempt" => meta.attempt}
    transaction = Transaction.start(Transaction.generate_id(), :background_job)

    transaction
    |> Transaction.set_action("#{meta.worker}#perform")
    |> Transaction.set_meta_data(metadata)
    |> Transaction.set_sample_data("params", meta.args)
    |> Transaction.record_event("worker.perform", "", "", measurement.duration, 0)
    |> Transaction.finish()

    transaction
  end

  defp normalize_error(%{kind: :error, error: error, stack: stack}) do
    {reason, message} = Error.metadata(error)
    {inspect(reason), inspect(message), stack}
  end

  defp normalize_error(%{kind: kind, error: error, stack: stack}) do
    {inspect(kind), inspect(error), stack}
  end
end
