defmodule Glific.Flows.First do
  @moduledoc """
  Random experiments on how to process flows emitted
  by nyaruka floweditor
  """

  @test_file "/json/language.json"

  alias Glific.{
    Contacts,
    Flows.Context,
    Flows.Flow
  }

  @doc """
  iex module for us to interact with our actions and events
  """
  @spec init() :: {Flow.t(), map()}
  def init do
    File.read!(__DIR__ <> @test_file)
    |> Jason.decode!()
    |> remove_definition()
    # lets get rid of stuff we msdon't use
    |> Map.delete("_ui")
    |> Flow.process(%{})
  end

  defp remove_definition(json) do
    if Map.has_key?(json, "definition"),
      do: json["definition"],
      else: json
  end

  @doc """
  A simple runner function to step the flow through multiple arguments. Should stop
  when we are either done, or return an error
  """
  @spec run([[]]) :: any
  def run(args) do
    {flow, uuid_map} = init()
    contact = Contacts.get_contact!(1)
    context = Flow.context(flow, uuid_map, contact)

    Enum.reduce_while(
      args,
      {:ok, context},
      fn arg, {:ok, context} ->
        case Context.execute(context, arg) do
          {:ok, context, []} -> {:cont, {:ok, context}}
          {:error, msg} -> {:halt, {:error, msg}}
          {:ok, _context, messages} -> {:halt, {:error, messages}}
        end
      end
    )
  end
end
