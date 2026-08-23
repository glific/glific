defmodule Glific.AI.Tool.Context do
  @moduledoc """
  The acting identity and run position passed explicitly into `Glific.AI.Tool.run/2`.

  `Glific.AI.Actor.put!/2` sets the same organisation and user into the process
  dictionary, because that is what `Repo` reads. This struct exists in addition to that: it
  is what tool code reads. A tool must never call `Repo.get_current_user()` or
  `Repo.get_organization_id()` itself — it takes `organization_id` and `user` from the
  `Context` it is given, so its behaviour is a pure function of its arguments and testable
  without any process-dictionary setup.
  """

  alias Glific.Users.User

  @enforce_keys [:organization_id, :user, :request_id, :step_index]
  defstruct [:organization_id, :user, :request_id, :step_index]

  @type t :: %__MODULE__{
          organization_id: non_neg_integer(),
          user: User.t(),
          request_id: String.t(),
          step_index: non_neg_integer()
        }
end
