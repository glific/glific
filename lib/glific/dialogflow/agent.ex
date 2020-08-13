defmodule Glific.Dialogflow.Agent do
  @moduledoc """
  Helper to get information about the agent
  """

  alias Glific.Dialogflow

  @doc """
  Get the agent that we are talking with for this specific project
  """
  @spec get() :: tuple
  def get do
    Dialogflow.request(:get, "", "")
  end
end
