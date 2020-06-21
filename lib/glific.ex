defmodule Glific do
  @moduledoc """
  Glific keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.

  For now we'll keep some commonly used functions here, until we need
  a new file
  """

  @doc """
  Wrapper to return :ok/:error when parsing strings to potential integers
  """
  @spec parse_maybe_integer(String.t() | integer) :: {:ok, integer} | :error
  def parse_maybe_integer(value) when is_integer(value),
    do: {:ok, value}
  def parse_maybe_integer(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      {_num, _rest} -> :error
      :error -> :error
    end
  end

end
