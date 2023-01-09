defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false
  # alias Glific.Repo

  def get_kpi(_kpi) do
    Enum.random(100..1000)
  end

  def kpi_list() do
    [
      :conversation_count,
      :active_flow_count,
      :contact_count,
      :opted_in_contacts_count,
      :opted_out_contacts_count
    ]
  end
end
