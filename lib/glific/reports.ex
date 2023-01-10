defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Messages.MessageConversation,
    Repo
  }

  @kpis %{
    contacts: Contact,
    conversation: MessageConversation
  }

  @doc false
  @spec get_kpi(String.t()) :: integer()
  def get_kpi(_kpi) do
    Enum.random(100..1000)
  end

  @doc false
  @spec kpi_list() :: list()
  def kpi_list do
    [
      :conversation_count,
      :active_flow_count,
      :contact_count,
      :opted_in_contacts_count,
      :opted_out_contacts_count
    ]
  end

  @doc """
  Returns last 7 days kpi data map with keys as date and value as count

    ## Examples

      iex> get_kpi_data(1, :contacts)
          %{
            "04-01-2023" => 0,
            "05-01-2023" => 0,
            "06-01-2023" => 0,
            "07-01-2023" => 0,
            "08-01-2023" => 2,
            "09-01-2023" => 3,
            "10-01-2023" => 10
          }
  """
  @spec get_kpi_data(non_neg_integer(), atom()) :: map()
  def get_kpi_data(organization_id, kpi) do
    get_kpi_date_keys()
    |> get_kpi_data_stats(organization_id, kpi)
  end

  # Returns last 7 days datetime which can then be used in query
  @spec get_kpi_date_keys() :: list()
  defp get_kpi_date_keys() do
    Enum.reduce(0..6, [], fn day, acc ->
      DateTime.utc_now()
      |> Timex.shift(days: -day)
      |> Timex.beginning_of_day()
      |> then(&(acc ++ [&1]))
    end)
  end

  # Query the KPI data and stitches it together in a map
  @spec get_kpi_data_stats(list(), non_neg_integer(), atom()) :: map()
  defp get_kpi_data_stats(days, organization_id, kpi) do
    Enum.reduce(days, %{}, fn day, acc ->
      next_day = Timex.shift(day, days: 1)
      date_key = Timex.format!(day, "{0D}-{0M}-{YYYY}")
      module = Map.get(@kpis, kpi)

      Repo.one(
        from(p in module,
          select: count("*"),
          where:
            p.organization_id == ^organization_id and
              p.inserted_at >= ^day and
              p.inserted_at < ^next_day
        )
      )
      |> then(&Map.put(acc, date_key, &1))
    end)
  end
end
