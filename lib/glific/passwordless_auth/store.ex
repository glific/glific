defmodule PasswordlessAuth.Store do
  @moduledoc """
  Agent for storing verification codes
  """
  use Agent

  @doc false
  def start_link(_) do
    Agent.start_link(fn -> Map.new() end, name: __MODULE__)
  end
end
