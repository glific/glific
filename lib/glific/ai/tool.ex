defmodule Glific.AI.Tool do
  @moduledoc """
  Behaviour for a single tool an AI skill's model may call mid-run.

  A tool is a pure description plus a `run/2` callback: a name and parameter schema the
  model sees, and a function the runtime invokes once the model asks for it. `run/2` receives
  the model's arguments and a `Glific.AI.Tool.Context` carrying who is acting and which
  organisation they belong to — a tool must read identity from that struct, never from
  `Repo.get_current_user()` (see `Glific.AI.Tool.Context`).

  Implement a tool with `use Glific.AI.Tool`, which injects `@behaviour` and defaults for
  `required_role/0` and `max_result_bytes/0`.

  ## `description/0` is prompt copy

  `description/0` is not internal documentation — it is text the model reads on every turn
  that includes this tool. Changing it changes the prompt, and therefore the behaviour and
  the cache key, for every skill whose `tools/0` lists this module. Review it like product
  copy, not like a code comment.
  """

  alias Glific.AI.Tool.Context

  @default_max_result_bytes 32_768

  @doc "Unique tool name, snake_case, shown to the model."
  @callback name() :: String.t()

  # This is prompt copy, not a code comment — see the moduledoc.
  @doc "Description shown to the model. Read every editor's docs before changing it."
  @callback description() :: String.t()

  @doc "The tool's argument schema, in any form `ReqLLM.Tool.new/1` accepts as `parameter_schema`."
  @callback parameters() :: keyword() | map()

  @doc "Minimum role required to invoke this tool. See `Glific.Users.Roles`."
  @callback required_role() :: atom()

  @doc "Runs the tool with the model-supplied `args` and the acting `Context`."
  @callback run(args :: map(), context :: Context.t()) :: {:ok, term()} | {:error, String.t()}

  @doc "Upper bound, in bytes, on the result serialised back to the model."
  @callback max_result_bytes() :: pos_integer()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Glific.AI.Tool

      @doc false
      @spec required_role() :: atom()
      @impl true
      def required_role, do: :staff

      @doc false
      @spec max_result_bytes() :: pos_integer()
      @impl true
      def max_result_bytes, do: unquote(@default_max_result_bytes)

      defoverridable required_role: 0, max_result_bytes: 0
    end
  end
end
