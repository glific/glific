defmodule Glific.Flows.Periodic do
  @moduledoc """
  A central place to define and execute all periodic flows. The current periodic flows in
  priority order are:

  Monthly, Weekly, Daily
  A specific weekday (i.e - Monday, Tuesday, ..)
  OutOfOffice

  All these flows are shortcode driven for now.

  At some point, we will make this fleixible and let the NGO define the periodic interval
  """

  @periodic_flows [
    "monthly",
    "weekly",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
    "daily",
    "outofoffice"
  ]
  @doc """
  Fill the state flow values with a shortcode -> id map, so we can proceed
  through our periodic jobs quickly. Maybe move this to the ETS cache table
  """
  @spec map_flow_ids(map()) :: map()
  defp map_flow_ids(%{flows: %{filled: true}} = state), do: state

  defp map_flow_ids(state) do
    shortcode_id_map = Repo.label_id_map(Glific.Flows.Flow, @periodic_flows, :shortcode)
    Map.put(state, flows, Map.merge(shortcode_id_map, %{filled: true}))
  end

  @spec compute_time(DateTime.t(), String.t()) :: DateTime.t()
  def compute_time(now, "monthly"), do: Timex.beginning_of_month(now)
  def compute_time(now, "weekly"), do: Timex.beginning_of_week(now, :mon)
  def compute_time(now, "outofoffice"), do: Glific.go_back_time(24, now, :hour)

  def compute_time(now, period)
      when period in [
             "monday",
             "tuesday",
             "wednesday",
             "thursday",
             "friday",
             "saturday",
             "sunday",
             "daily"
           ],
      do: Timex.beginning_of_day(now)

  def run_periodic_flows(state, contact_id) do
  end
  @spec periodic_flow(map(), String.t(), non_neg_integer, DateTime.t()) :: {map(), boolean}
  def periodic_flow(state, period, contact_id, since) do
    state = map_flow_ids(state)
    flow_id = get_in(state, [:flows, period])

    if !is_nil(flow_id) and
    !Flows.flow_activated(flow_id, contact_id, since) do
      {:ok, flow} = Flows.get_cached_flow("outofoffice", %{shortcode: "outofoffice"})
      FlowContext.init_context(flow, message.contact)
      {state, true}
    else
      {state, false}
    end
  end

  @spec dayname_flow(map(), String.t(), non_neg_integer, DateTime.t()) :: {map(), boolean}
  def dayname_flow(state, dayname, contact_id, since) do
    if Timex.day_name(Date.day_of_week(since)) == Timex.day_to_num(dayname),
      do: periodic_flow(state, dayname, contact_id, since),
      else: {state, false}
  end

  @spec out_of_office_flow(map(), non_neg_integer, DateTime.t()) :: {map(), boolean}
  def out_of_office_flow(state, contact_id, since) do
    # lets  check if we should initiate the out of office flow
    # lets do this only if we've not sent them the out of office flow
    # in the past 24 hours
    if FunWithFlags.enabled?(:out_of_office_active),
      do: periodic_flow(state, "outofoffice", contact_id, since),
      else: {state, false}
  end
end
