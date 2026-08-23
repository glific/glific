defmodule Glific.AI.Runtime.State do
  @moduledoc """
  In-memory state for a single `Glific.AI.Runtime.step/1` call.

  Scoped to one Oban job — `Glific.AI.StepWorker` builds a fresh `State` at the top of every
  `perform/1`, from the conversation row, `Glific.AI.build_context/1`, and
  `Glific.AI.Credentials.fetch/2`, and discards it once that job returns. Nothing in `State` is
  ever persisted or sent across a process boundary, so it is the one place in the agent runtime
  allowed to hold a live API key.
  """

  alias Glific.AI.Conversation
  alias Glific.AI.Runtime.State
  alias Glific.Users.User
  alias ReqLLM.Context

  @enforce_keys [
    :conversation,
    :skill,
    :user,
    :context,
    :step_index,
    :organization_id,
    :tools,
    :api_key
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          conversation: Conversation.t(),
          skill: module(),
          user: User.t(),
          context: Context.t(),
          step_index: non_neg_integer(),
          organization_id: non_neg_integer(),
          tools: [module()],
          api_key: String.t()
        }

  @doc """
  Builds the initial state for a run's first `Glific.AI.Runtime.step/1` call.
  """
  @spec new(keyword()) :: State.t()
  def new(fields) do
    struct!(__MODULE__, Keyword.put_new(fields, :tools, fields[:skill].tools()))
  end
end
