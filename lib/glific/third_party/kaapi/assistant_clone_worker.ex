defmodule Glific.ThirdParty.Kaapi.AssistantCloneWorker do
  @moduledoc """
  Worker for cloning an assistant by creating a new assistant with the same
  configuration (model, prompt, knowledge base) and prefixing "Copy of"
  to the assistant name.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 2
end
