defmodule Glific.State.Flow do
  @moduledoc """
  Manage flow state and allocation to ensure we only have one user modify
  a flow at a time
  """
  require Logger
  import Ecto.Query, warn: false

  alias Glific.{
    Flows.Flow,
    Repo,
    State,
    Users.User
  }

  @doc """
  Check if there is an available flow for this user
  - If available, return the available flow
  - If none available, return error message along with name of user currently using flow
  """
  @spec get_flow(User.t(), non_neg_integer, map) :: {Flow.t(), map}
  def get_flow(user, flow_id, state) do
    organization_id = user.organization_id

    {org_state, flow} =
      State.get_state(state, organization_id)
      |> State.free_entity(:flows, user)
      |> get_org_flows(user, flow_id)

    {flow, Map.put(state, organization_id, org_state)}
  end

  @spec get_org_flows(map(), User.t(), non_neg_integer()) :: {map, Flow.t()}
  defp get_org_flows(
         %{
           free_simulators: free_simulators,
           busy_simulators: busy_simulators,
           free_flows: free,
           busy_flows: busy
         } = state,
         user,
         flow_id
       ) do
    key = {user.id, user.fingerprint}
    organization_id = user.organization_id

    [flow] =
      Flow
      |> where([f], f.organization_id == ^organization_id)
      |> where([f], f.id == ^flow_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    available_flow = if(Enum.member?(free, flow), do: flow, else: nil)

    cond do
      # when user already has some flow assigned with same fingerprint
      Map.has_key?(busy, key) ->
        {assigned_flow, _time} = Map.get(busy, key)

        requested_flow =
          if assigned_flow == flow,
            do: assigned_flow,
            else: available_flow

        # updating free flows list when a new flow is assigned to user
        available_flows = if assigned_flow == flow, do: free, else: free ++ [assigned_flow]

        {
          %{
            free_simulators: free_simulators,
            busy_simulators: busy_simulators,
            free_flows: Enum.uniq(available_flows) -- [requested_flow],
            busy_flows: Map.put(busy, key, {requested_flow, DateTime.utc_now()})
          },
          requested_flow
        }

      # when the requested flow is either not available in flow or if all the flows are busy
      is_nil(available_flow) || Enum.empty?(free) ->
        Repo.put_process_state(user.organization_id)
        user_name = get_user_name(state, flow)

        {state,
         {:ok,
          %{
            errors: %{
              key: "error",
              message:
                "Sorry! You cannot edit the flow right now. It is being edited by \n #{user_name}"
            }
          }}}

      # when the flow is available and user is assigned a flow
      is_struct(available_flow) ->
        {
          %{
            free_simulators: free_simulators,
            busy_simulators: busy_simulators,
            free_flows: free -- [available_flow],
            busy_flows: Map.put(busy, key, {flow, DateTime.utc_now()})
          },
          available_flow
        }

      true ->
        Logger.info(
          "Error fetching flow #{available_flow} for organization_id #{organization_id} for user #{
            user.name
          }"
        )

        {state,
         {:ok,
          %{
            errors: %{
              key: "error",
              message: "Something went wrong"
            }
          }}}
    end
  end

  @spec get_user_name(map(), Flow.t()) :: String.t()
  defp get_user_name(state, requested_flow) do
    state.busy_flows
    |> Enum.reduce("", fn busy_flow, acc ->
      {key, value} = busy_flow
      {flow, _time} = value
      {user_id, _finger_print} = key
      if flow.id == requested_flow.id, do: Glific.Users.get_user!(user_id).name, else: acc
    end)
  end
end
