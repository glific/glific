defmodule Glific.Flowex.Agent do
  @moduledoc """
  Helper to get information about the agent
  """

  alias Glific.Flowex

  @doc """
  Get the agent that we are talking with for this specific project
  """
  @spec get(String.t()) :: tuple
  def get(project) do
    Flowex.request(project, :get, "", "")
  end
end
