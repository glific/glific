defmodule Glific.Navanatech do
  @moduledoc """
  Glific Navanatech for all api calls to navatech
  """

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec navatech_post(map()) :: map()
  def navatech_post(fields) do
    Process.sleep(2000)
    %{response: fields["response"]}
  end
end
