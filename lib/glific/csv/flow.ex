defmodule Glific.CSV.Flow do
  @moduledoc """
  Given a CSV model, and a tracking shortcode, generate the json flow for the CSV
  incorporating the UUID's used in previous conversions. Store the latest UUID mapping
  back in the database
  """

  @doc """
  Given a file, generate the flow for it that matches floweditor input
  """
  @spec gen_flow :: nil
  def gen_flow do
  end
end
