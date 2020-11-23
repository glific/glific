defmodule Glific.Appsignal do
  @moduledoc """
  A simple interface that connect Oban job status to Appsignal
  """

  alias Appsignal.Transaction

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:oban, :job, event], measurement, meta, _)
      when event in [:stop, :exception] do
    transaction = record_event(measurement, meta)

    if event == :exception && meta.attempt >= meta.max_attempts do
      context = inspect(Map.take(meta, [:id, :args, :queue, :worker]))
      Transaction.set_error(transaction, meta.error, context, meta.stacktrace)
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
end
