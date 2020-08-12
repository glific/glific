defmodule Glific.Dialogflow.Agent do
  @moduledoc """
  Helper to get information about the agent
  """

  alias Glific.Dialogflow

  @doc """
  Get the agent that we are talking with for this specific project
  """
  @spec get(String.t()) :: tuple
  def get(project) do
    Dialogflow.request(project, :get, "", "")
  end
end
