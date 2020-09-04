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
  use Publicist

  alias Glific.{
    Flows,
    Flows.Flow,
    Flows.FlowContext,
    Messages.Message,
    Partners,
    Repo
  }

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

  # Fill the state flow values with a shortcode -> id map, so we can proceed
  # through our periodic jobs quickly. Maybe move this to the ETS cache table
  @spec map_flow_ids(map()) :: map()
  defp map_flow_ids(%{flows: %{filled: true}} = state), do: state

  defp map_flow_ids(state) do
    shortcode_id_map = Repo.label_id_map(Flow, @periodic_flows, :shortcode)

    organization = Partners.organization()

    shortcode_id_map =
      if organization.out_of_office.enabled,
        do: Map.put(shortcode_id_map, "outofoffice", organization.out_of_office.flow_id),
        else: shortcode_id_map

    Map.put(state, :flows, Map.merge(shortcode_id_map, %{filled: true}))
  end

  # Compute the offset for the time, so we can check if there is a flow running
  # for that specific periodic event already
  @spec compute_time(DateTime.t(), String.t()) :: DateTime.t()
  defp compute_time(now, "monthly"), do: Timex.beginning_of_month(now)
  defp compute_time(now, "weekly"), do: Timex.beginning_of_week(now, :mon)
  defp compute_time(now, "outofoffice"), do: Glific.go_back_time(24, now, :hour)

  defp compute_time(now, period)
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

  @doc """
  Run all the periodic flows in priority order. Stop when we find the first one that we can execute
  """
  @spec run_flows(map(), Message.t()) :: map()
  def run_flows(state, message) do
    now = DateTime.utc_now()
    state = map_flow_ids(state)

    Enum.reduce_while(
      @periodic_flows,
      state,
      fn period, state ->
        since = compute_time(now, period)
        {state, result} = periodic_flow(state, period, message, since)

        if result,
          do: {:halt, state},
          else: {:cont, state}
      end
    )
  end

  @spec common_flow(map(), String.t(), Message.t(), DateTime.t()) :: {map(), boolean}
  defp common_flow(state, period, message, since) do
    flow_id = get_in(state, [:flows, period])

    if !is_nil(flow_id) and
         !Flows.flow_activated(flow_id, message.contact_id, since) do
      {:ok, flow} = Flows.get_cached_flow(flow_id, %{id: flow_id})
      FlowContext.init_context(flow, message.contact)
      {state, true}
    else
      {state, false}
    end
  end


  # Run a specific flow and do flow specific checks in the local files, before we invoke the
  # common function to process all periodic flows
  @spec periodic_flow(map(), String.t(), Message.t(), DateTime.t()) :: {map(), boolean}
  defp periodic_flow(state, period, message, since)
      when period in [
             "monday",
             "tuesday",
             "wednesday",
             "thursday",
             "friday",
             "saturday",
             "sunday"
           ] do
    if Date.day_of_week(since) == Timex.day_to_num(period),
      do: common_flow(state, period, message, since),
      else: {state, false}
  end

  defp periodic_flow(state, "outofoffice" = period, message, since) do
    # lets  check if we should initiate the out of office flow
    # lets do this only if we've not sent them the out of office flow
    # in the past 24 hours
    if FunWithFlags.enabled?(:out_of_office_active),
      do: common_flow(state, period, message, since),
      else: {state, false}
  end

  defp periodic_flow(state, period, message, since),
    do: common_flow(state, period, message, since)
end
