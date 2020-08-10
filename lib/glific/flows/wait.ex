defmodule Glific.Flows.Wait do
  @moduledoc """
  The Wait object which encapsulates the wait for a router
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Flows.Router
  }

  @required_fields [:type]

  @type t() :: %__MODULE__{
          type: String.t() | nil,
          seconds: non_neg_integer | nil,
          category_uuid: :uuid | nil
        }

  embedded_schema do
    field :type, :string
    field :seconds, :integer
    field :category_uuid, Ecto.UUID
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Router.t()) :: {Wait.t(), map()}
  def process(json, uuid_map, _router) do
    Flows.check_required_fields(json, @required_fields)

    wait = %Wait{
      type: json["type"],
      seconds: json["timeout"]["seconds"],
      category_uuid: json["timeout"]["category_uuid"]
    }

    {wait, uuid_map}
  end

  @doc """
  Execute a exit, given a message stream.
  """
  @spec execute(Wait.t(), FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()}
  def execute(nil, context, _message_stream),
    do: {:ok, context, []}

  def execute(wait, context, _message_stream) do
    if is_nil(wait.seconds) do
      {:ok, context, []}
    else
      {:ok, context} =
        FlowContext.update_flow_context(
          context,
          %{wakeup_at: DateTime.add(DateTime.utc_now(), wait.seconds)}
        )

      {:ok, context, []}
    end
  end
end
