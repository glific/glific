defmodule Glific.Navanatech do
  @moduledoc """
  Glific Navanatech for all api calls to navatech
  """

  def navatech_post(fields) do
    Process.sleep(2000)
    %{response: fields["response"]}
  end
end
