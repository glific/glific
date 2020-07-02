defmodule Glific.Flows.First do
  @moduledoc """
  Random experiments on how to process flows emitted
  by nyaruka floweditor
  """

  @test_file "lib/glific/flows/help.json"

  def init do
    File.read!(@test_file)
    |> Jason.decode!()
    # lets get rid of stuff we domnt use
    |> Map.delete("_ui")
  end
end
