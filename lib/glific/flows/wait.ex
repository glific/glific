defmodule Glific.Flows.Wait do
  @moduledoc """
  The Wait object which encapsulates the wait for a router
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Router,
    Messages.Message
  }

  @required_fields [:type]

  @type t() :: %__MODULE__{
          type: String.t() | nil,
          seconds: non_neg_integer | nil,
          category_uuid: :uuid | nil,
          expression: String.t()
        }

  embedded_schema do
    field :type, :string
    field :seconds, :integer
    field :category_uuid, Ecto.UUID
    field :expression, :string
  end

  @doc """
  Process a json structure from flow editor to the Glific data types
  """
  @spec process(map(), map(), Router.t()) :: {Wait.t(), map()}
  def process(json, uuid_map, _router) do
    Flows.check_required_fields(json, @required_fields)

    wait = %Wait{
      type: json["type"],
      seconds: json["timeout"]["seconds"],
      category_uuid: json["timeout"]["category_uuid"],
      expression: json["timeout"]["expression"]
    }

    {wait, uuid_map}
  end

  @spec type_of_next_message(Flow.t(), Wait.t()) :: atom()
  defp type_of_next_message(flow, wait) do
    # lets keep this simple for now, we'll just go follow the exit of this
    # action to the next node

    {:category, category} = flow.uuid_map[wait.category_uuid]
    {:exit, exit} = flow.uuid_map[category.exit_uuid]

    {:node, dest_node} = flow.uuid_map[exit.destination_node_uuid]
    [action | _] = dest_node.actions

    if is_nil(action.templating),
      do: :session,
      else: :hsm
  rescue
    # in case any of the uuids don't exist, we just trap the exception
    _result -> :unknown
  end

  @doc """
  Validate a wait, this is a no-op
  """
  @spec validate(Wait.t(), Keyword.t(), map()) :: Keyword.t()
  def validate(wait, errors, flow) do
    cond do
      is_nil(wait.seconds) ->
        errors

      wait.seconds >= 24 * 60 * 60 and
          type_of_next_message(flow, wait) == :session ->
        [
          {Message, "The next message after a long no response should be a template", "Warning"}
          | errors
        ]

      true ->
        errors
    end
  end

  @doc """
  Execute a wait, given a message stream.
  """
  @spec execute(Wait.t(), FlowContext.t(), [Message.t()]) ::
          {:ok, FlowContext.t() | nil, [Message.t()]} | {:error, String.t()}
  def execute(nil, context, _messages),
    do: {:ok, context, []}

  def execute(wait, context, _messages) do
    wait_seconds = get_wait_timeout(wait, context)

    if wait_seconds > 0 do
      {:ok, context} =
        FlowContext.update_flow_context(
          context,
          %{wakeup_at: DateTime.add(DateTime.utc_now(), wait_seconds)}
        )

      {:ok, context, []}
    else
      {:ok, context, []}
    end
  end

  ## Check if the wait for response is dynamic.
  @spec get_wait_timeout(map(), FlowContext.t()) :: integer()
  defp get_wait_timeout(%{expression: expression} = _wait, context)
       when expression not in ["", nil] do
    {:ok, seconds} =
      FlowContext.parse_context_string(context, expression)
      |> Glific.execute_eex()
      |> Glific.parse_maybe_integer()

    seconds
  end

  defp get_wait_timeout(wait, _), do: wait.seconds || 0
end
