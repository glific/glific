defmodule Glific.Dialogflow.SessionWorker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :dialogflow,
    max_attempts: 1,
    priority: 0

  alias Glific.Dialogflow.Sessions


  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{
        args: %{
          "path" => path,
          "locale" => locale,
          "message" => message,
          "context_id" => context_id,
          "result_name" => result_name,
        }}) do
    Sessions.make_request(
      Glific.atomize_keys(message),
      path, locale,
      [context_id: context_id, result_name: result_name])
    :ok
  end
end
