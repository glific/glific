defmodule Glific.Flows.First do
  @moduledoc """
  Random experiments on how to process flows emitted
  by nyaruka floweditor
  """

  @test_file "/json/help.json"

  alias Glific.Flows.Flow

  @doc """
  iex module for us to interact with our actions and events
  """
  @spec init([String.t]) :: {Flow.t(), map()}
  def init(message_stream) do
    {flow, uuid_map} =
      File.read!(__DIR__ <> @test_file)
      |> Jason.decode!()
      # lets get rid of stuff we msdon't use
      |> Map.delete("_ui")
      |> Flow.process(%{})

    Flow.execute(flow, uuid_map, message_stream)
  end


end
